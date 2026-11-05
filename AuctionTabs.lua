local _, M = ...

local sections = {
  {label='Shopping', view='shopping'},
  {label='Selling', view='selling'},
  {label='Canceling', view='my auctions'},
  {label='Market', view='market'},
}

local function dock(self, page, view)
  local window = self.window
  local ah = AuctionHouseFrame
  self.auctionDock = {
    page=page, anchor={window:GetPoint()}, scale=window:GetScale(),
    strata=window:GetFrameStrata(), level=window:GetFrameLevel(),
  }
  -- Keep the terminal on UIParent. Native tab pages can still be laying out
  -- during OnShow; the already visible AH has the authoritative dimensions.
  local scaleRatio = ah:GetEffectiveScale()/UIParent:GetEffectiveScale()
  local fit = math.min((ah:GetWidth()-16)/1040, (ah:GetHeight()-44)/680)
  if fit <= 0 then error('Auction House dimensions unavailable') end
  window:SetFrameStrata(ah:GetFrameStrata())
  window:SetFrameLevel(ah:GetFrameLevel()+10)
  window:SetMovable(false)
  window:SetClampedToScreen(false)
  window:ClearAllPoints()
  window:SetScale(fit*scaleRatio)
  window:SetPoint('CENTER', ah, 'CENTER', 0, -14/fit)
  self.selectedRow = nil
  self:SetView(view)
  self:RenderUI()
  if view == 'my auctions' and self:CanUseAuctionHouse() then
    self:RequestOwnedAuctionsDiagnostic()
  end
end

local function undock(self, page)
  local state = self.auctionDock
  if not state or state.page ~= page then return end
  self.auctionDock = nil
  local window = self.window
  window:Hide()
  window:SetFrameStrata(state.strata)
  window:SetFrameLevel(state.level)
  window:SetMovable(true)
  window:SetClampedToScreen(true)
  window:SetScale(state.scale)
  window:ClearAllPoints()
  window:SetPoint(unpack(state.anchor, 1, 5))
end

function M:CloseMarketWindow()
  if self.auctionDock then
    AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
  else
    self.window:Hide()
  end
end

function M:InstallAuctionTabs()
  local ah = AuctionHouseFrame
  if self.auctionTabs or not self.window or not ah or not ah.Tabs or #ah.Tabs == 0 then return end
  local lib = LibStub and LibStub('LibAHTab-1-0', true)
  local tabs = {}
  if not lib then
    hooksecurefunc(ah, 'SetDisplayMode', function()
      for _, tab in ipairs(tabs) do
        tab.page:Hide()
        PanelTemplates_DeselectTab(tab.button)
      end
    end)
  end

  local previous = ah.Tabs[#ah.Tabs]
  for _, section in ipairs(sections) do
    local view, label = section.view, section.label
    local id = 'VoidMarkMarket'..label
    local page = CreateFrame('Frame', nil, ah)
    page:SetPoint('TOPLEFT', ah, 'TOPLEFT', 8, -36)
    page:SetPoint('BOTTOMRIGHT', ah, 'BOTTOMRIGHT', -8, 8)
    page:Hide()
    local errorLabel = page:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    errorLabel:SetPoint('CENTER')
    errorLabel:SetWidth(500)
    page:SetScript('OnShow', function()
      errorLabel:SetText('')
      local ok, reason = pcall(dock, self, page, view)
      if not ok then
        undock(self, page)
        local message = label..' could not open: '..tostring(reason)
        self:Log('AUCTION TAB', message)
        errorLabel:SetText(message)
      end
    end)
    page:SetScript('OnHide', function() undock(self, page) end)
    local title = 'VoidMark Market - '..label
    local button
    if lib then
      -- Share the same row manager when Auctionator (or another host) supplies it.
      lib:CreateTab(id, page, 'VM '..label, title)
      button = lib:GetButton(id)
    else
      button = CreateFrame('Button', id..'Tab', ah, 'AuctionHouseFrameDisplayModeTabTemplate')
      button:SetText(label)
      PanelTemplates_TabResize(button, 14, nil, 70)
      button:SetPoint('TOPLEFT', previous, 'TOPRIGHT', 3, 0)
      PanelTemplates_DeselectTab(button)
      button:SetScript('OnClick', function()
        ah:SetDisplayMode({})
        for _, native in ipairs(ah.Tabs) do PanelTemplates_DeselectTab(native) end
        PanelTemplates_SelectTab(button)
        ah:SetTitle(title)
        page:Show()
      end)
      previous = button
    end
    tabs[#tabs+1] = {button=button, page=page}
  end
  self.auctionTabs = tabs
end

local function installAfterOpen()
  -- Blizzard creates the AH on demand. Let its opening handlers finish first.
  if C_Timer and C_Timer.After then C_Timer.After(0, function() M:InstallAuctionTabs() end)
  else M:InstallAuctionTabs() end
end
M:RegisterHandler('AUCTION_HOUSE_SHOW', installAfterOpen)


-- Handle either load order if the Blizzard auction UI loads after the AH event.
if EventUtil and EventUtil.ContinueOnAddOnLoaded then
  EventUtil.ContinueOnAddOnLoaded('Blizzard_AuctionHouseUI', installAfterOpen)
end
