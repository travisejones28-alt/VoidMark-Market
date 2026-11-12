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
-- Newest completed full scan, this character's or the synced partner's.
function M:NewestFullScanAt()
 local t=self.db.latestScan and tonumber(self.db.latestScan.completedAt) or nil
 local peer=self.db.syncPeer and self.db.shareReceived and self.db.shareReceived[self.db.syncPeer]
 local p=peer and tonumber(peer.scanAt)
 if p and (not t or p>t) then t=p end
 if t and t>time()+60 then return nil end
 return t
end
function M:TooltipAgeText(at)
 local age=math.max(0,time()-at)
 return age>=86400 and math.floor(age/86400)..'d' or age>=3600 and math.floor(age/3600)..'h' or math.max(1,math.floor(age/60))..'m'
end
-- Auctionator-style: a Vendor line and an Auction line, plus the stack total
-- when hovering a stack. Old prices are greyed with their age.
local function vendorPrice(link)
 local info=C_Item and C_Item.GetItemInfo or GetItemInfo
 if not info then return end
 local ok,_,_,_,_,_,_,_,_,_,_,sell=pcall(info,link)
 sell=ok and tonumber(sell)
 return sell and sell>0 and sell or nil
end
function M:AppendMarketTooltip(tip,link,count)
 if not self.db or not tip then return end
 count=tonumber(count);if not (count and count>1 and count%1==0 and count<=10000) then count=nil end
 if self.db.settings.tooltipVendor==true then
  local v=vendorPrice(link)
  if v then tip:AddDoubleLine(count and ('Vendor x'..count) or 'Vendor',self:Coins(v*(count or 1)),1,.82,0,1,1,1) end
 end
 local key=self:LinkIdentity(link)
 if not key then return end -- unresolved variant: never borrow another variant's price
 local p=self:PriceObservation(key)
 if not p then
  if self.db.settings.tooltipNoData~=false and not bindBlocksAuction(link) then
   tip:AddDoubleLine('Auction','|cff999999No price yet|r',1,.82,0,.6,.6,.6)
  end
  return
 end
 local stale=time()-p.at>self.db.settings.maxDataAge or p.unverified
 local name=stale and ('Auction |cff999999('..self:TooltipAgeText(p.at)..' old)|r') or 'Auction'
 -- A full scan (here or on the synced character) ran after this price was last
 -- seen: the item isn't on the AH right now. Say so instead of just "14h old".
 local scan=self:NewestFullScanAt()
 if scan and p.at<scan-300 and not p.unverified then
  name='Auction |cff999999(none listed now, last seen '..self:TooltipAgeText(p.at)..' ago)|r'
 end
 local r,g,b=1,1,1;if stale or name:find('none listed',1,true) then r,g,b=.6,.6,.6 end
 tip:AddDoubleLine(name,self:Coins(p.floor),1,.82,0,r,g,b)
 if count then tip:AddDoubleLine('Auction x'..count,self:Coins(p.floor*count),1,.82,0,r,g,b) end
end
-- Item ID from a link, for checking that a slot really holds the hovered item.
local function linkItemID(link)
 return type(link)=='string' and tonumber(link:match('item:(%d+)')) or nil
end
-- Mail APIs return (name, itemID, texture, count, quality, canUse) on current
-- clients and (name, texture, count, quality, canUse) on older ones. The
-- trailing canUse boolean (or a matching item ID) tells the shapes apart.
local function mailCount(want,a,b,c,d,e,f)
 if type(f)=='boolean' or (want and b==want) then return tonumber(d) end
 if type(e)=='boolean' then return tonumber(c) end
 return nil
end
-- Stack size of the hovered item. Only trusted when we can prove the source:
-- a mail attachment slot, or a bag slot that holds this exact item. Any button
-- with a GetID (mail, merchant, bank tabs...) used to be read as "bag slot N",
-- which showed another item's stack size.
function M:TooltipStackCount(tip,link)
 local owner=tip and tip.GetOwner and tip:GetOwner()
 if type(owner)~='table' then return end
 local name=owner.GetName and owner:GetName()
 if type(name)=='string' then
  local i=tonumber(name:match('^SendMailAttachment(%d+)$'))
  if i then return GetSendMailItem and mailCount(linkItemID(link),GetSendMailItem(i)) or nil end
  i=tonumber(name:match('^OpenMailAttachmentButton(%d+)$'))
  if i then
   local mail=InboxFrame and InboxFrame.openMailID
   return mail and GetInboxItem and mailCount(linkItemID(link),GetInboxItem(mail,i)) or nil
  end
 end
 if not owner.GetID then return end
 local slot=owner:GetID()
 local bag=owner.GetBagID and owner:GetBagID() or (owner.GetParent and owner:GetParent() and owner:GetParent().GetID and owner:GetParent():GetID())
 if type(bag)~='number' or type(slot)~='number' then return end
 local want=linkItemID(link)
 if C_Container and C_Container.GetContainerItemInfo then
  local info=C_Container.GetContainerItemInfo(bag,slot)
  if type(info)~='table' then return end
  if want and info.itemID and info.itemID~=want then return end
  if want and not info.itemID and linkItemID(info.hyperlink)~=want then return end
  return info.stackCount
 elseif GetContainerItemInfo then
  local _,count,_,_,_,_,slotLink=GetContainerItemInfo(bag,slot)
  if want and linkItemID(slotLink)~=want then return end
  return count
 end
end
function M:InitializePriceTooltips()
 if self.tooltipHooked then return end
 self.tooltipHooked=true
 local function append(tip)
  if not tip or not tip.GetItem then return end
  local _,link=tip:GetItem()
  if link then
   local ok,count=pcall(self.TooltipStackCount,self,tip,link)
   self:AppendMarketTooltip(tip,link,ok and count or nil)
   if self.AppendDisenchantTooltip then pcall(self.AppendDisenchantTooltip,self,tip,link) end
   if self.AppendBoughtTooltip then pcall(self.AppendBoughtTooltip,self,tip,link) end
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
