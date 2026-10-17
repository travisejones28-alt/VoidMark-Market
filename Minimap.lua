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

  -- Position relative to the current minimap size, not a fixed 82px
  -- radius (which leaves buttons in the center of enlarged square maps).
  local lastWidth, lastHeight, lastShape
  local function position(angle)
    local width, height = Minimap:GetWidth(), Minimap:GetHeight()
    if not width or not height or width <= 0 or height <= 0 then return end
    local radians = math.rad(angle)
    local dx, dy = math.cos(radians), math.sin(radians)
    local shape = GetMinimapShape and GetMinimapShape() or 'ROUND'
    local x, y
    if shape == 'SQUARE' then
      -- Ray from center to the perimeter of a rectangular/square minimap.
      local multiplier = math.max(math.abs(dx) / (width / 2), math.abs(dy) / (height / 2))
      if multiplier < 0.00001 then return end
      x, y = dx / multiplier, dy / multiplier
    else
      -- Standard circular minimap; keep a little clearance outside the rim.
      x, y = dx * (width / 2), dy * (height / 2)
    end
    local clearance = 9
    x = x + (x > 0 and clearance or -clearance)
    y = y + (y > 0 and clearance or -clearance)
    b:ClearAllPoints()
    b:SetPoint('CENTER', Minimap, 'CENTER', x, y)
    lastWidth, lastHeight, lastShape = width, height, shape
  end
  local function updatePosition()
    local x, y = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not scale or scale == 0 then return end
    x, y = x / scale, y / scale
    local cx, cy = Minimap:GetCenter()
    if not cx or not cy then return end
    local angle = math.deg(math.atan2(y - cy, x - cx))
    saved.angle = angle
    position(angle)
  end
  local sinceCheck = 0
  b:SetScript('OnUpdate', function(_, elapsed)
    if b.dragging then
      updatePosition()
      return
    end
    sinceCheck = sinceCheck + elapsed
    if sinceCheck < 0.25 then return end
    sinceCheck = 0
    local w, h = Minimap:GetWidth(), Minimap:GetHeight()
    local shape = GetMinimapShape and GetMinimapShape() or 'ROUND'
    if w ~= lastWidth or h ~= lastHeight or shape ~= lastShape then
      position(saved.angle)
    end
  end)
  b:SetScript('OnDragStart', function(self)
    self.dragging = true
  end)
  b:SetScript('OnDragStop', function(self)
    self.dragging = false
    updatePosition()
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
