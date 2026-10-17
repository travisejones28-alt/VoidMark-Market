local _, M = ...
-- Standalone minimap launcher; no optional libraries required.
function M:InitializeMinimapButton()
  if self.minimapButton or not self.db then return end
  local cfg = self.root.settings
  cfg.minimap = type(cfg.minimap) == 'table' and cfg.minimap or {}
  local saved = cfg.minimap
  if type(saved.angle) ~= 'number' or saved.angle ~= saved.angle then saved.angle = 225 end
  if type(saved.hide) ~= 'boolean' then saved.hide = false end

  local b = CreateFrame('Button', 'VoidMarkMarketMinimapButton', Minimap)
  self.minimapButton = b
  b:SetSize(31, 31)
  b:SetFrameStrata('MEDIUM')
  b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  b:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
  b:RegisterForDrag('LeftButton')
  b:SetMovable(true)
  b:EnableMouse(true)
  local icon = b:CreateTexture(nil, 'ARTWORK')
  icon:SetTexture('Interface\\Icons\\INV_Misc_Coin_01')
  icon:SetSize(19, 19)
  icon:SetPoint('CENTER')
  local border = b:CreateTexture(nil, 'OVERLAY')
  border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
  border:SetSize(53, 53)
  border:SetPoint('TOPLEFT', 0, 0)
  local highlight = b:CreateTexture(nil, 'HIGHLIGHT')
  highlight:SetTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
  highlight:SetBlendMode('ADD')
  highlight:SetAllPoints(b)

  local function position(angle)
    local radians = math.rad(angle)
    b:ClearAllPoints()
    b:SetPoint('CENTER', Minimap, 'CENTER', math.cos(radians) * 82, math.sin(radians) * 82)
  end
  local function updatePosition()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale == 0 then return end
    x, y = x / scale, y / scale
    local cx, cy = Minimap:GetCenter()
    local angle = math.deg(math.atan2(y - cy, x - cx))
    saved.angle = angle
    position(angle)
  end
  b:SetScript('OnDragStart', function(self)
    self.dragging = true
    self:SetScript('OnUpdate', updatePosition)
  end)
  b:SetScript('OnDragStop', function(self)
    self.dragging = false
    self:SetScript('OnUpdate', nil)
  end)
  b:SetScript('OnClick', function(_, mouseButton)
    if mouseButton == 'RightButton' then M:SetView('settings')
    else M:ToggleUI() end
  end)
  b:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:AddLine('VoidMark Market', 0.68, 0.45, 1)
    GameTooltip:AddLine('Left-click: Open / close', 1, 1, 1)
    GameTooltip:AddLine('Right-click: Settings', 1, 1, 1)
    GameTooltip:AddLine('Drag: Move icon', 1, 1, 1)
    GameTooltip:Show()
  end)
  b:SetScript('OnLeave', function() GameTooltip:Hide() end)
  position(saved.angle)
  b:SetShown(not saved.hide)
end

function M:SetMinimapIconVisible(visible)
  if not self.root or not self.root.settings then return end
  local cfg = self.root.settings
  cfg.minimap = type(cfg.minimap) == 'table' and cfg.minimap or {}
  cfg.minimap.hide = not visible
  if self.minimapButton then self.minimapButton:SetShown(visible) end
end
