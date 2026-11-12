local _, M = ...

-- Auctionator-style tabs on the Auction House tab row: three trading screens
-- (the Flips tab was removed in 1.12.0)
-- plus one VoidMark tab for everything else (scanning, history, settings...).
local sections = {
  {key='shopping', label='Shopping', root='browse'},
  {key='selling', label='Selling', root='selling'},
  {key='cancelling', label='Listings', root='my auctions'},  -- key kept for saved settings
  {key='flipledger', label='Flip Ledger', id='FlipLedger', root='flip ledger'},
  {key='voidmark', label='VoidMark'},
}
local toolViews = {market=true, banker=true, vendor=true, crafting=true, settings=true, tools=true, sync=true}
M.auctionSections = sections

function M:AuctionStartView(section)
  if section and section.root then return section.root end
  local v = self.db and self.db.settings.lastAuctionView
  return toolViews[v] and v or 'market'
end
function M:RememberAuctionView(view)
  if self.auctionDock and self.dockSection=='voidmark' and toolViews[view] and self.db then
    self.db.settings.lastAuctionView = view
  end
end
function M:DockRootView()
  for _, section in ipairs(sections) do if section.key==self.dockSection then return section.root end end
end

local function fitDock(self)
  local state, ah, window = self.auctionDock, AuctionHouseFrame, self.window
  if not state or not ah then return end
  -- Scale the fixed 1040x680 layout into the current AH content area so a
  -- resized/rescaled AH (or MoveAny) never clips the controls.
  local fit = math.min((ah:GetWidth()-16)/1040, (ah:GetHeight()-44)/680)
  if not (fit and fit > 0) then error('Auction House dimensions unavailable') end
  window:ClearAllPoints()
  window:SetScale(fit)
  window:SetPoint('CENTER', ah, 'CENTER', 0, -14/fit)
end

local function dock(self, page, view, section)
  local window = self.window
  self.dockSection = section
  local ah = AuctionHouseFrame
  self.auctionDock = {
    page=page, anchor={window:GetPoint()}, scale=window:GetScale(),
    strata=window:GetFrameStrata(), level=window:GetFrameLevel(), parent=window:GetParent(),
  }
  -- Keep the controls in the same frame hierarchy when the AH is raised or
  -- dragged. Use the AH bounds even if the new page has not laid out yet.
  window:SetParent(page)
  window:SetToplevel(false)
  window:SetFrameStrata(ah:GetFrameStrata())
  window:SetFrameLevel(page:GetFrameLevel()+1)
  if window.SetFixedFrameLevel then window:SetFixedFrameLevel(false) end
  window:SetMovable(false)
  window:SetClampedToScreen(false)
  fitDock(self)
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
local function moveAnyLoaded(ah)
  if moveAnyControls(ah) then return true end
  return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('MoveAny') and true or false
end

local function savePosition(self, ah)
  if self.persistenceBlocked or moveAnyLoaded(ah) or not ah.GetPoint then return end
  local point, relative, relativePoint, x, y = ah:GetPoint()
  if type(point)~='string' or not self:Finite(x,-1e5,1e5) or not self:Finite(y,-1e5,1e5) then return end
  if relative and relative~=UIParent then return end -- only store screen-relative anchors
  self.db.settings.auctionPoint = {point=point, relativePoint=relativePoint or point, x=x, y=y}
end

function M:RestoreAuctionPosition()
  local ah = AuctionHouseFrame
  if not ah or moveAnyLoaded(ah) then return end
  local p = self.db and self.db.settings.auctionPoint
  if type(p)=='table' and type(p.point)=='string' and self:Finite(p.x,-1e5,1e5) and self:Finite(p.y,-1e5,1e5) then
    ah:ClearAllPoints()
    ah:SetPoint(p.point, UIParent, p.relativePoint or p.point, p.x, p.y)
  end
  local saved = self.db and self.db.settings.auctionScale
  if self:Finite(saved,.5,2.5) then ah:SetScale(saved) end
end

function M:ResetAuctionLayout()
  if self.persistenceBlocked then return end
  self.db.settings.auctionPoint, self.db.settings.auctionScale = nil, nil
  local ah = AuctionHouseFrame
  if ah and not moveAnyLoaded(ah) then
    ah:SetScale(1)
    if ah.IsShown and ah:IsShown() and ShowUIPanel and HideUIPanel then HideUIPanel(ah); ShowUIPanel(ah) end
  end
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
    if ah.SetClampedToScreen then ah:SetClampedToScreen(true) end
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
    savePosition(self, ah)
  else
    self.ahGrip:SetScript('OnUpdate',nil)
    if not self.persistenceBlocked then self.db.settings.auctionScale=ah:GetScale() end
    if self.auctionDock then pcall(fitDock, self) end
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
  -- Any empty part of the Auction House (native tabs included) drags the
  -- whole window. Hooks add to Blizzard handlers instead of replacing them.
  if ah.HookScript then
    ah:HookScript('OnMouseDown',function(_,button) if button=='LeftButton' then beginGesture(self,button) end end)
    ah:HookScript('OnMouseUp',function(_,button) if button=='LeftButton' then endGesture(self,button) end end)
    ah:HookScript('OnHide',function() endGesture(self) end)
    ah:HookScript('OnSizeChanged',function() if self.auctionDock then pcall(fitDock,self) end end)
  end
  if not moveAnyLoaded(ah) then self:RestoreAuctionPosition() end
end

local function undock(self, page)
  local state = self.auctionDock
  if not state or state.page ~= page then return end
  local window = self.window
  self:StopMarketDrag(window)
  self.auctionDock = nil
  self.dockSection = nil
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

-- Taint safety: addon code must never write Auction House state (display
-- mode, selected tab). Blizzard's bag-click handler reads that state, and if
-- an addon wrote it, using any bag item while the AH is open is blocked
-- ("VoidMarkMarket has been blocked from an action only available to the
-- Blizzard UI"). Our pages are opaque overlays on top of the native content;
-- the native display mode is left exactly as Blizzard set it.
local function showNative(self)
  local ah = AuctionHouseFrame
  for _, tab in ipairs(self.auctionTabs or {}) do
    tab.page:Hide()
    if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(tab.button) end
  end
  local selected = ah and ah.Tabs and PanelTemplates_GetSelectedTab and PanelTemplates_GetSelectedTab(ah)
  local native = selected and ah.Tabs[selected]
  if native and PanelTemplates_SelectTab then PanelTemplates_SelectTab(native) end
end
M.ShowNativeAuctionView = showNative

function M:CloseMarketWindow()
  if self.auctionDock then
    showNative(self)
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

  local auctionator = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded('Auctionator')
  local previous = ah.Tabs[#ah.Tabs]
  for _, section in ipairs(sections) do
    local page = CreateFrame('Frame', nil, ah)
    page:SetPoint('TOPLEFT', ah, 'TOPLEFT', 8, -36)
    page:SetPoint('BOTTOMRIGHT', ah, 'BOTTOMRIGHT', -8, 8)
    -- Sit above the native Buy/Sell/Auctions content and hide it visually.
    -- 1.22.5: +200 (was +30). The native Auctions view's own "Auctions/Bids"
    -- tabs sit higher than +30 and showed through over the Market title. We
    -- only raise our page; Blizzard's frames are never hidden or changed (taint).
    page:SetFrameLevel(ah:GetFrameLevel()+200)
    local shade = page:CreateTexture(nil, 'BACKGROUND')
    shade:SetAllPoints(page)
    shade:SetColorTexture(.035, .02, .055, 1)
    page:Hide()
    -- The margins around the docked window also drag the whole AH.
    page:EnableMouse(true)
    page:SetScript('OnMouseDown',function(_,button) if button=='LeftButton' then beginGesture(self,button) end end)
    page:SetScript('OnMouseUp',function(_,button) if button=='LeftButton' then endGesture(self,button) end end)
    local errorLabel = page:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
    errorLabel:SetPoint('CENTER')
    errorLabel:SetWidth(500)
    page:SetScript('OnShow', function()
      errorLabel:SetText('')
      local ok, reason = pcall(dock, self, page, self:AuctionStartView(section), section.key)
      if not ok then
        undock(self, page)
        local message = section.label..' could not open: '..tostring(reason)
        self:Log('AUCTION TAB', message)
        errorLabel:SetText(message)
      end
    end)
    page:SetScript('OnHide', function() endGesture(self); undock(self, page) end)
    -- Prefix only when Auctionator's own Shopping/Selling tabs are also shown.
    local label = (auctionator and section.key~='voidmark') and ('VM '..section.label) or section.label
    local id = 'VoidMarkMarket'..(section.id or section.label)
    local button
    if lib then
      -- Share the same row manager when Auctionator (or another host) supplies it.
      lib:CreateTab(id, page, label, 'VoidMark Market - '..section.label)
      button = lib:GetButton(id)
    else
      button = CreateFrame('Button', id..'Tab', ah, 'AuctionHouseFrameDisplayModeTabTemplate')
      button:SetText(label)
      PanelTemplates_TabResize(button, 14, nil, 60)
      button:SetPoint('TOPLEFT', previous, 'TOPRIGHT', 3, 0)
      PanelTemplates_DeselectTab(button)
      button:SetScript('OnClick', function()
        -- No ah:SetDisplayMode here (see showNative): it taints bag item use.
        for _, native in ipairs(ah.Tabs) do PanelTemplates_DeselectTab(native) end
        for _, other in ipairs(tabs) do if other.button~=button then other.page:Hide();PanelTemplates_DeselectTab(other.button) end end
        PanelTemplates_SelectTab(button)
        page:Show()
      end)
      previous = button
    end
    tabs[#tabs+1] = {button=button, page=page, key=section.key}
  end
  self.auctionTabs = tabs
end

local function installAfterOpen()
  -- Blizzard creates the AH on demand. Let its opening handlers finish first.
  if C_Timer and C_Timer.After then
    C_Timer.After(0, function()
      local first = not M.auctionTabs
      M:InstallAuctionTabs()
      -- The UI panel manager re-anchors the AH on every open.
      if not first and AuctionHouseFrame and not moveAnyLoaded(AuctionHouseFrame) then M:RestoreAuctionPosition() end
    end)
  else
    local first = not M.auctionTabs
    M:InstallAuctionTabs()
    if not first and AuctionHouseFrame and not moveAnyLoaded(AuctionHouseFrame) then M:RestoreAuctionPosition() end
  end
end
M:RegisterHandler('AUCTION_HOUSE_SHOW', installAfterOpen)


-- Handle either load order if the Blizzard auction UI loads after the AH event.
if EventUtil and EventUtil.ContinueOnAddOnLoaded then
  EventUtil.ContinueOnAddOnLoaded('Blizzard_AuctionHouseUI', installAfterOpen)
end
