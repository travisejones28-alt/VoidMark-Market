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
 -- Forever links drop the suffix: if the price on file is another suffix's
 -- (tooltip title says "of Intellect", the scan said "of the Sorcerer"), use
 -- the entry with this exact name, or show no price.
 local title=self:TooltipTitle(tip)
 local state,sf=self:VariantPrice(key,title,self:LinkName(link))
 if state=='none' then tip:AddDoubleLine('Auction','|cff999999No price for this suffix yet|r',1,.82,0,.6,.6,.6);return end
 local p
 if state=='suffix' then p={floor=sf.floor,at=sf.at} else p=self:PriceObservation(key) end
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

-- Title line of a tooltip (the item's full name), without colour codes.
function M:TooltipTitle(tip)
 local nm=tip and tip.GetName and tip:GetName();local fs=nm and _G[nm..'TextLeft1']
 if not (fs and fs.GetText) then return nil end
 local ok,v=pcall(fs.GetText,fs)
 if not ok or type(v)~='string' or v=='' then return nil end
 return (v:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))
end

-- Item identity on WoW Forever --------------------------------------------------
-- Forever's item links leave out the random suffix: a bag link says "[Pagan
-- Belt]" while the AH sells "Pagan Belt of Intellect" and "Pagan Belt of the
-- Sorcerer" as different items (different AH item keys). So:
--  * link keys (LinkIdentity) for suffix gear are suffix 0 and shared by every suffix;
--  * AH keys (from searches, your auctions, purchases) carry the real suffix;
--  * names are the reliable bridge: tooltip title / AH name = full name.
-- Everything that matches items goes through NameScore / ItemMatcher.
local function lo(s) return type(s)=='string' and s~='' and s:lower() or nil end
local function extends(full,base) full,base=lo(full),lo(base);return full~=nil and base~=nil and #full>#base+4 and full:sub(1,#base+4)==base..' of ' end
M.NameExtends=function(_,full,base) return extends(full,base) end
function M:LinkName(link) local n=type(link)=='string' and link:match('%[(.-)%]');return n~='' and n or nil end
-- 2 = same name, 1 = one is the base name of the other (suffix unknown), 0 = different.
function M:NameScore(a,b)
 a,b=lo(a),lo(b);if not a or not b then return 0 end
 if a==b then return 2 end
 if extends(a,b) or extends(b,a) then return 1 end
 return 0
end
-- Matcher for one item (o.link, o.name = full name if known, o.key = AH key if
-- known). Returns f(name,key) -> 2 certain, 1 possible (a record saved
-- without its suffix), 0 no.
function M:ItemMatcher(o)
 o=o or {}
 local base=self:LinkName(o.link)
 -- Only an AH key (o.key) is trusted to tell suffixes apart by number; a
 -- link's own suffix field can't be compared with AH numbers.
 local K,fromAH=o.key,o.key~=nil;if K==nil and o.link then K=self:LinkIdentity(o.link) end
 local _,kid,ks=self:ParseKey(K)
 local full=o.name
 if not base then base=full end
 local T
 if extends(full,base) then T=lo(full)
 elseif K~=nil and (ks or 0)~=0 and self.KeyFullName then
  local kn=self:KeyFullName(K);if kn and (extends(kn,base) or lo(kn)~=lo(base)) then T=lo(kn);if lo(base)==lo(kn) then T=nil end end
 end
 local B=lo(base)
 if T and B and not extends(T,B) then B=T:match('^(.-) of ') or B end
 return function(nm,k)
  local _,id,s=self:ParseKey(k)
  if kid and id and id~=kid then return 0 end
  -- Two AH keys with suffixes decide it.
  if kid and id and (ks or 0)~=0 and (s or 0)~=0 then
   if s==ks then return 2 end
   -- Different numbers: certain for AH keys; for a link's number, the full
   -- name (when known) decides instead.
   if fromAH or not T then return 0 end
  end
  local C=lo(nm)
  if C and B and C==B and id and (s or 0)~=0 and self.KeyFullName then local kn=self:KeyFullName(k);if kn then C=lo(kn) end end
  if not C then return 0 end
  if T then
   if C==T then return 2 end
   if C==B then return 1 end
   return 0
  end
  if B then
   if C==B then return 2 end
   if extends(C,B) then return 1 end
  end
  return 0
 end
end

-- Which scan price fits an item whose full name is known (tooltip/AH name)?
-- 'key' = the key's own price is this item's; 'suffix', e = this suffix's own
-- price from a scan that saw several suffixes; 'none' = only other suffixes'
-- prices are on file.
function M:VariantPrice(key,fullName,base)
 local m=key~=nil and self.db.market[key]
 if type(fullName)~='string' or fullName=='' then return 'key' end
 if not m then
  -- Only a synced price (no names) for a suffix item under a link key that
  -- every suffix shares: it may be another suffix's.
  local _,_,s=self:ParseKey(key)
  if base and (s or 0)==0 and self:NameScore(fullName,base)==1 then return 'none' end
  return 'key'
 end
 local sf=type(m.suffixFloors)=='table' and m.suffixFloors[fullName]
 if type(sf)=='table' and self:Finite(sf.floor,1,1e12) then return 'suffix',sf end
 local name=type(m.name)=='string' and m.name or nil
 if m.mixedVariants then
  -- Mixed key and this name wasn't listed in that scan.
  if name and name:lower()==fullName:lower() then return 'key' end
  return 'none'
 end
 if name and name:lower()~=fullName:lower() and (name:find(' of ',1,true) or (base and self:NameScore(fullName,base)==1)) then
  if self:NameScore(name,fullName)==0 or name:find(' of ',1,true) then return 'none' end
 end
 return 'key'
end
