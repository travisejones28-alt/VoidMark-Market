local _, M = ...

local sections = {
  {label='Shopping', view='shopping'},
  {label='Selling', view='selling'},
  {label='Canceling', view='my auctions'},
  {label='Market', view='market'},
}

local function dock(self, page, view)
  local window = self.window
  self.auctionDock = {
    page=page, anchor={window:GetPoint()}, scale=window:GetScale(),
    strata=window:GetFrameStrata(), parent=window:GetParent(),
  }
  window:StopMovingOrSizing()
  window:SetParent(page)
  window:SetFrameStrata('PARENT')
  window:SetMovable(false)
  window:SetClampedToScreen(false)
  window:ClearAllPoints()
  -- The terminal has a fixed logical size. Fit its controls inside the AH chrome.
  window:SetScale(math.min(page:GetWidth()/1040, page:GetHeight()/680))
  window:SetPoint('CENTER', page, 'CENTER')
  self.selectedRow = nil
  self:SetView(view)
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
  window:SetParent(state.parent)
  window:SetFrameStrata(state.strata)
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
    page:SetScript('OnShow', function() dock(self, page, view) end)
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
