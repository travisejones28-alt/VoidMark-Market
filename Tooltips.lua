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
function M:StoredPriceObservation(key)
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
local function bindBlocksAuction(link)
 local info=C_Item and C_Item.GetItemInfo or GetItemInfo
 if not info then return false end
 local ok,_,_,_,_,_,_,_,_,_,_,_,_,_,bind=pcall(info,link)
 return ok and (bind==1 or bind==4) -- bind on pickup / quest items never reach the AH
end
function M:TooltipAgeText(at)
 local age=math.max(0,time()-at)
 return age>=86400 and math.floor(age/86400)..'d' or age>=3600 and math.floor(age/3600)..'h' or math.max(1,math.floor(age/60))..'m'
end
-- Compact: price per unit, optional stack total, one source/age line and the
-- historical estimate only while the observation is current.
function M:AppendMarketTooltip(tip,link,count)
 if not self.db or not tip then return end
 local key=self:LinkIdentity(link)
 if not key then return end -- unresolved variant: never borrow another variant's price
 local p=self:PriceObservation(key)
 if not p then
  if self.db.settings.tooltipNoData~=false and not bindBlocksAuction(link) then
   tip:AddDoubleLine('VoidMark Market','No AH price yet',.76,.56,1,.6,.6,.6)
  end
  return
 end
 local age=math.max(0,time()-p.at)
 local stale=age>self.db.settings.maxDataAge or p.unverified
 tip:AddDoubleLine('VoidMark AH / unit',self:Money(p.floor),.76,.56,1,1,.85,.4)
 count=tonumber(count)
 if count and count>1 and count%1==0 and count<=10000 then
  tip:AddDoubleLine('  Stack of '..count,self:Money(p.floor*count),.75,.8,.85,1,.85,.4)
 end
 local state=stale and '|cffff6655STALE / UNVERIFIED|r' or '|cff72e7aaCURRENT|r'
 tip:AddLine(state..' '..p.source..' | '..self:TooltipAgeText(p.at)..' old',.75,.8,.85)
 if not stale and p.fair then
  local note=p.confidence and (' ('..math.floor(p.confidence+0.5)..'%)') or ''
  if p.developing or not p.confidence then note=note..' provisional' end
  tip:AddDoubleLine('Market estimate'..note,self:Money(p.fair),.75,.8,.85,.75,.8,.85)
 end
end
-- Stack size of the hovered bag slot, when the tooltip owner is a bag button.
function M:TooltipStackCount(tip)
 local owner=tip and tip.GetOwner and tip:GetOwner()
 if type(owner)~='table' or not owner.GetID then return end
 local slot=owner:GetID()
 local bag=owner.GetBagID and owner:GetBagID() or (owner.GetParent and owner:GetParent() and owner:GetParent().GetID and owner:GetParent():GetID())
 if type(bag)~='number' or type(slot)~='number' then return end
 if C_Container and C_Container.GetContainerItemInfo then
  local info=C_Container.GetContainerItemInfo(bag,slot);return type(info)=='table' and info.stackCount or nil
 elseif GetContainerItemInfo then
  local _,count=GetContainerItemInfo(bag,slot);return count
 end
end
function M:InitializePriceTooltips()
 if self.tooltipHooked then return end
 self.tooltipHooked=true
 local function append(tip)
  if not tip or not tip.GetItem then return end
  local _,link=tip:GetItem()
  if link then
   local ok,count=pcall(self.TooltipStackCount,self,tip)
   self:AppendMarketTooltip(tip,link,ok and count or nil)
  end
 end
 if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,function(tip) pcall(append,tip) end)
 else
  for _,tip in pairs({GameTooltip,ItemRefTooltip,ShoppingTooltip1,ShoppingTooltip2}) do
   if tip.HookScript then pcall(tip.HookScript,tip,'OnTooltipSetItem',function(t) pcall(append,t) end) end
  end
 end
end
