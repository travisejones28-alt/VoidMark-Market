local _,M=...
-- A market key is an auction identity, never the first cached item with the same ID.
function M:LinkIdentity(link,expectedID)
 if type(link)~='string' then return end
 local pet,petLevel=link:match('battlepet:(%d+):(%d+)')
 if pet then
  local id=expectedID or 82800
  return self:Key(id,0,tonumber(petLevel),tonumber(pet)),id,0,tonumber(petLevel),tonumber(pet)
 end
 local payload=link:match('item:([%d:%-]+)')
 if not payload then return end
 local fields={}; for v in (payload..':'):gmatch('(.-):') do fields[#fields+1]=v end
 local id,suffix=tonumber(fields[1]),tonumber(fields[7]) or 0
 if expectedID and id~=expectedID then return end
 local level=0
 -- Enchants and instance IDs do not define an AH variant. Bonus/upgrade gear
 -- needs its effective level; do not guess a base price if metadata is missing.
 local instant=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
 if instant then
  local _,_,_,equip=instant(link)
  if equip==nil then return end
  if equip~='' and equip~='INVTYPE_BAG' and equip~='INVTYPE_NON_EQUIP_IGNORE' then
   local fn=C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
   level=fn and fn(link); if not self:Finite(level,1,1e6) then return end
  end
 elseif tonumber(fields[13] or 0) and tonumber(fields[13] or 0)>0 then return end
 return self:Key(id,suffix,level,0),id,suffix,level,0
end
function M:PriceObservation(key)
 if not self.db or not key then return end
 local m=self.db.market[key];local localPrice
 if m and type(m.latest)=='table' and self:Finite(m.latest.floor,1,1e12) and self:Finite(m.lastSeen,1,time()+60) then
  localPrice={floor=m.latest.floor,at=m.lastSeen,fair=self:CanEstimateResale(m) and m.fairValue or nil,
   confidence=self:Finite(m.confidenceScore,0,100) and m.confidenceScore or nil,
   developing=m.developingMarket~=false and
    ((tonumber(m.observations) or 0)<6 or (tonumber(m.historySpan) or 0)<3*86400 or (tonumber(m.confidenceScore) or 0)<70),
   source='Local scan',unverified=m.cacheUntrusted or m.analysisIncomplete}
 end
 local p=self.db.sharedPrices[key]
 local sharedHistory=p and (p.histFair or (p.reliable and p.fair))
 local histAt=p and (p.histAt or (p.reliable and p.at))
 if not self:Finite(histAt,time()-self.db.settings.maxDataAge,time()+60) then sharedHistory=nil end
 if localPrice and not localPrice.fair then localPrice.fair=sharedHistory end
 if p and self:Finite(p.floor,1,1e12) and self:Finite(p.at,1,time()+60) and
   (not localPrice or p.at>localPrice.at or (p.at==localPrice.at and localPrice.unverified)) then
  return {floor=p.floor,at=p.at,fair=sharedHistory or (localPrice and localPrice.fair),
   confidence=self:Finite(p.confidence,0,100) and p.confidence or (localPrice and localPrice.confidence),
   developing=true,source='Synced account'}
 end
 return localPrice
end
function M:TooltipMarketForLink(link)
 local key=self:LinkIdentity(link)
 return key and self:PriceObservation(key)
end
function M:AppendMarketTooltip(tip,link)
 local p=self:TooltipMarketForLink(link);if not p then return end
 local age=math.max(0,time()-p.at)
 local ageText=age>=86400 and math.floor(age/86400)..'d' or age>=3600 and math.floor(age/3600)..'h' or math.floor(age/60)..'m'
 tip:AddLine('VoidMark Market',.76,.56,1)
 tip:AddDoubleLine('Observed AH / unit',self:Money(p.floor),.95,.95,.95,1,.85,.4)
 tip:AddLine(p.source..' | '..ageText..' old | '..self:SyncTime(p.at),.75,.8,.85)
 if age>self.db.settings.maxDataAge or p.unverified then tip:AddLine('STALE / UNVERIFIED',1,.4,.3)
 else
  if p.fair then tip:AddDoubleLine('Market estimate',self:Money(p.fair),.75,.8,.85,.75,.8,.85) end
  if p.confidence then
   tip:AddLine('Model confidence: '..math.floor(p.confidence+0.5)..'%',.75,.8,.85)
  else
   tip:AddLine('Model confidence: not yet shared',.75,.8,.85)
  end
  if p.developing or not p.confidence then
   tip:AddLine('Developing Market - estimate is provisional',1,.75,.3)
  end
 end
end
function M:InitializePriceTooltips()
 if self.tooltipHooked then return end
 self.tooltipHooked=true
 local function append(tip)
  if not tip or not tip.GetItem then return end
  local _,link=tip:GetItem();if link then self:AppendMarketTooltip(tip,link) end
 end
 if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,function(tip) pcall(append,tip) end)
 else
  for _,tip in pairs({GameTooltip,ItemRefTooltip,ShoppingTooltip1,ShoppingTooltip2}) do
   if tip.HookScript then pcall(tip.HookScript,tip,'OnTooltipSetItem',append) end
  end
 end
end
