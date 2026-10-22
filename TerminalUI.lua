local _,M=...
function M:SortBrowseRows()
  local mode=self.db.settings.sort
  table.sort(self.browseRows or {},function(a,b)
    local av,bv
    if mode=='ask' then av,bv=a.floor or 0,b.floor or 0
    elseif mode=='profit' then av,bv=(a.fair or 0)-(a.floor or 0),(b.fair or 0)-(b.floor or 0)
    elseif mode=='roi' then av,bv=(a.floor or 0)>0 and a.fair/a.floor or 0,(b.floor or 0)>0 and b.fair/b.floor or 0 end
    if av and av~=bv then return mode=='ask' and av<bv or mode~='ask' and av>bv end
    if a.name~=b.name then return a.name<b.name end
    return tostring(a.marketKey)<tostring(b.marketKey)
  end)
end
function M:SaveWindowLayout()
  if self.persistenceBlocked then return end
  local f=self.window
  local point,_,relative,x,y=f:GetPoint()
  local scale=f:GetScale()
  if type(point)~='string' or type(relative)~='string' or not self:Finite(x,-10000,10000)
    or not self:Finite(y,-10000,10000) or not self:Finite(scale,0.4,1.5) then return end
  self.db.settings.window={point=point,relative=relative,x=x,y=y,scale=scale}
end
function M:RestoreWindowLayout()
  local w=self.db.settings.window
  local anchors={CENTER=true,TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}
  if type(w)~='table' then return end
  if anchors[w.point] and anchors[w.relative] and self:Finite(w.x,-10000,10000) and self:Finite(w.y,-10000,10000) then
    self.window:ClearAllPoints();self.window:SetPoint(w.point,UIParent,w.relative,w.x,w.y)
  end
  if self:Finite(w.scale,0.4,1.5) then self.window:SetScale(math.min(w.scale,self:MaximumWindowScale())) end
end
function M:MaximumWindowScale()
  return math.max(0.4,math.min(1.5,(UIParent:GetWidth()-30)/1040,(UIParent:GetHeight()-30)/680))
end
function M:ChangeWindowScale(delta,reset)
  local scale=reset and 1 or (self.window:GetScale() or 1)+delta
  self.window:SetScale(math.max(0.4,math.min(self:MaximumWindowScale(),scale)))
  self:SaveWindowLayout()
end
function M:ShowRowTooltip(row)
  if not GameTooltip or not row.data then return end
  local o=row.data;local m=o.marketKey and self.db.market[o.marketKey]
  local id=o.itemID or m and m.itemID
  if not id then return end
  GameTooltip:SetOwner(row,'ANCHOR_RIGHT')
  -- Use the exact link when available; item ID fallback is labeled as base metadata.
  if o.itemLink then GameTooltip:SetHyperlink(o.itemLink)
  else GameTooltip:SetItemByID(id);GameTooltip:AddLine('Base item metadata; prices use the selected variant.',0.7,0.6,0.9,true) end
  GameTooltip:Show()
end
function M:FinancialSummaryText()
  local lines={'BOOKED RESULTS (UTC day buckets; recording begins with v1.3)'}
  for _,p in ipairs(self:GetFinancialPeriods()) do
    lines[#lines+1]=p.days..'d: cost-matched result '..self:Money(p.realized)..' | fees '..self:Money(p.fees)..
      ' | uncosted revenue '..self:Money(p.uncosted)..' | ROI '..(p.roi and self:PercentText(p.roi) or 'N/A')
  end
  local history=self.db.wealthHistory[self.characterID] or {}
  local last=history[#history]
  if last then lines[#lines+1]='Recorded gold '..self:Money(last.gold)..' | estimated tracked wealth '..self:Money(last.gold+last.estimatedNet)..
    ' | unpriced cost '..self:Money(last.unpricedCost)..' | '..#history..' hourly observations' end
  lines[#lines+1]='Balance changes include mail, gifts and expenses; they are not trading profit.'
  return table.concat(lines,'\n')
end
function M:ShowHistoryWindow(row,wealth)
  if not wealth and (not row or not row.marketKey) then self:Print('Select a local item first');return end
  if not self.historyWindow then
    local f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');self.historyWindow=f
    f:SetSize(680,330);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetClampedToScreen(true)
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=16})
    f:SetBackdropColor(0.035,0.025,0.065,1);f:SetBackdropBorderColor(0.5,0.25,0.8,1)
    f.title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');f.title:SetPoint('TOPLEFT',18,-18);f.title:SetWidth(560)
    f.caption=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');f.caption:SetPoint('BOTTOMLEFT',18,18);f.caption:SetWidth(640);f.caption:SetJustifyH('LEFT')
    local close=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');close:SetSize(55,24);close:SetPoint('TOPRIGHT',-12,-12);close:SetText('Close');close:SetScript('OnClick',function()f:Hide()end)
    f.bars={}
    for i=1,60 do local b=f:CreateTexture(nil,'ARTWORK');b:SetColorTexture(0.61,0.35,0.95,0.95);f.bars[i]=b end
  end
  local points={}
  if wealth then
    local history=self.db.wealthHistory[self.characterID] or {}
    for i=math.max(1,#history-59),#history do local h=history[i];points[#points+1]={at=h.at,value=h.gold} end
  else points=self:GetPriceHistory(row.marketKey) end
  local f=self.historyWindow;f:Show()
  f.title:SetText(wealth and 'Recorded gold balance' or ('Scan medians: '..tostring(row.name or row.marketKey)))
  local high=1;local low
  for _,p in ipairs(points) do high=math.max(high,p.value);low=math.min(low or p.value,p.value) end
  for i,b in ipairs(f.bars) do
    local p=points[i];b:SetShown(p~=nil)
    if p then
      local width=620/math.max(1,#points)
      b:ClearAllPoints();b:SetPoint('BOTTOMLEFT',f,'BOTTOMLEFT',24+(i-1)*width,88)
      b:SetSize(math.max(1,width-2),math.max(1,180*p.value/high))
    end
  end
  f.caption:SetText(#points==0 and 'No local observations available. Shared prices do not create history.' or
    (#points..' observations | low '..self:Money(low)..' | high '..self:Money(high)..'\n'..
    date('%Y-%m-%d %H:%M',points[1].at)..' to '..date('%Y-%m-%d %H:%M',points[#points].at)..
    '\n'..(wealth and 'Gold only; gifts, mail and spending affect this balance. Not a profit chart.' or 'Chronological samples, evenly spaced; asking prices are not completed sales.')))
end
