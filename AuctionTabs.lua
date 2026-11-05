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
    strata=window:GetFrameStrata(), level=window:GetFrameLevel(), parent=window:GetParent(),
  }
  -- Keep the controls in the same frame hierarchy when the AH is raised or
  -- dragged. Use the AH bounds even if the new page has not laid out yet.
  local fit = math.min((ah:GetWidth()-16)/1040, (ah:GetHeight()-44)/680)
  if fit <= 0 then error('Auction House dimensions unavailable') end
  window:SetParent(page)
  window:SetToplevel(false)
  window:SetFrameStrata(ah:GetFrameStrata())
  window:SetFrameLevel(page:GetFrameLevel()+1)
  if window.SetFixedFrameLevel then window:SetFixedFrameLevel(false) end
  window:SetMovable(false)
  window:SetClampedToScreen(false)
  window:ClearAllPoints()
  window:SetScale(fit)
  window:SetPoint('CENTER', ah, 'CENTER', 0, -14/fit)
  self.selectedRow = nil
  self:SetView(view)
  self:RenderUI()
  if view == 'my auctions' and self:CanUseAuctionHouse() then
    self:RequestOwnedAuctionsDiagnostic()
  end
end

local function moveAnyControls(ah)
  return type(ah.MA_OnMouseDown)=='function' and type(ah.MA_OnMouseUp)=='function'
    and _G.AuctionHouseFrameMove ~= nil
end

local function beginGesture(self, button)
  if self.ahGesture or (button~='LeftButton' and button~='RightButton') or
     (InCombatLockdown and InCombatLockdown()) then return end
  local ah = AuctionHouseFrame
  local gesture = {button=button, managed=moveAnyControls(ah)}
  self.ahGesture=gesture
  if gesture.managed then
    ah:MA_OnMouseDown(ah, button)
  elseif button=='LeftButton' then
    gesture.wasMovable=ah:IsMovable()
    ah:SetMovable(true)
    ah:StartMoving()
  else
    local startX=GetCursorPosition()
    local scale=ah:GetScale()
    self.ahGrip:SetScript('OnUpdate',function()
      local x=GetCursorPosition()
      ah:SetScale(math.max(.5, math.min(2.5, scale+(x-startX)*.0024)))
    end)
  end
end

local function endGesture(self, button)
  local gesture=self.ahGesture
  if not gesture or (button and button~=gesture.button) then return end
  self.ahGesture=nil
  local ah=AuctionHouseFrame
  if gesture.managed then
    ah:MA_OnMouseUp(ah,gesture.button)
  elseif gesture.button=='LeftButton' then
    ah:StopMovingOrSizing()
    ah:SetMovable(gesture.wasMovable)
  else
    self.ahGrip:SetScript('OnUpdate',nil)
    if not self.persistenceBlocked then self.db.settings.auctionScale=ah:GetScale() end
  end
end

function M:StartMarketDrag(window)
  if self.auctionDock then beginGesture(self,'LeftButton');return end
  window:StartMoving()
end

function M:StopMarketDrag(window)
  if self.auctionDock then endGesture(self);return end
  window:StopMovingOrSizing()
  self:SaveWindowLayout()
end

local function installTitleGrip(self, ah)
  local grip=CreateFrame('Frame',nil,ah)
  self.ahGrip=grip
  grip:SetPoint('TOPLEFT',ah,'TOPLEFT',64,-3)
  grip:SetPoint('TOPRIGHT',ah,'TOPRIGHT',-34,-3)
  grip:SetHeight(20)
  grip:SetFrameLevel(ah:GetFrameLevel()+12)
  grip:EnableMouse(true)
  grip:SetScript('OnMouseDown',function(_,button) beginGesture(self,button) end)
  grip:SetScript('OnMouseUp',function(_,button) endGesture(self,button) end)
  grip:SetScript('OnHide',function() endGesture(self) end)
  local saved=self.db.settings.auctionScale
  local moveAnyLoaded=C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('MoveAny')
  if not moveAnyLoaded and not moveAnyControls(ah) and self:Finite(saved,.5,2.5) then ah:SetScale(saved) end
end

local function undock(self, page)
  local state = self.auctionDock
  if not state or state.page ~= page then return end
  local window = self.window
  self:StopMarketDrag(window)
  self.auctionDock = nil
  window:Hide()
  window:ClearAllPoints()
  window:SetParent(state.parent)
  window:SetToplevel(true)
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
  installTitleGrip(self,ah)
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
