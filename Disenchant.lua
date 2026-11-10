local _,M=...
-- Disenchant advisor: for one item, compare Disenchant (materials sold on the
-- AH), Vendor, and selling the item itself on the AH; say which pays most.
-- Yield tables: CraftShuffle 0.2.4 DEData.lua by Vystery (MIT licence),
-- vanilla tables with the WoW Forever weapon-essence change. Your own
-- disenchants are recorded per quality/type/5-level band and blended in, so
-- the estimates move toward what Forever really gives.
M.defaults.tooltipDisenchant=true
M.defaults.deVendorMargin=0.10 -- disenchant must beat vendor by more than this, or vendor it

local DISENCHANT_SPELL=13262
local LEARN_WEIGHT=10 -- the built-in table counts as this many casts
M.disenchantMats={
 [10940]='Strange Dust',[11083]='Soul Dust',[11137]='Vision Dust',[11176]='Dream Dust',[16204]='Illusion Dust',
 [10938]='Lesser Magic Essence',[10939]='Greater Magic Essence',[10998]='Lesser Astral Essence',[11082]='Greater Astral Essence',
 [11134]='Lesser Mystic Essence',[11135]='Greater Mystic Essence',[11174]='Lesser Nether Essence',[11175]='Greater Nether Essence',
 [16202]='Lesser Eternal Essence',[16203]='Greater Eternal Essence',
 [10978]='Small Glimmering Shard',[11084]='Large Glimmering Shard',[11138]='Small Glowing Shard',[11139]='Large Glowing Shard',
 [11177]='Small Radiant Shard',[11178]='Large Radiant Shard',[14343]='Small Brilliant Shard',[14344]='Large Brilliant Shard',
 [20725]='Nexus Crystal',
}
-- Uncommon: armor dust 75% / essence 20% / shard 5%; weapons swap dust and essence.
local UNCOMMON={
 {max=15,dust={10940,1,2},essence={10938,1,2}},
 {max=20,dust={10940,2,3},essence={10939,1,2},shard={10978,1,1}},
 {max=25,dust={10940,4,6},essence={10998,1,2},shard={10978,1,1},chances={0.75,0.15,0.10}},
 {max=30,dust={11083,1,2},essence={11082,1,2},shard={11084,1,1}},
 {max=35,dust={11083,2,5},essence={11134,1,2},shard={11138,1,1}},
 {max=40,dust={11137,1,2},essence={11135,1,2},shard={11139,1,1}},
 {max=45,dust={11137,2,5},essence={11174,1,2},shard={11177,1,1}},
 {max=50,dust={11176,1,2},essence={11175,1,2},shard={11178,1,1}},
 {max=55,dust={11176,2,5},essence={16202,1,2},shard={14343,1,1}},
 {max=60,dust={16204,1,2},essence={16203,1,2},shard={14344,1,1}},
 {max=65,dust={16204,2,5},essence={16203,2,3},shard={14344,1,1}},
}
local FOREVER_WEAPON_ESSENCE={min=21,max=30,essence={10939,1,2}} -- Forever: green weapons 21-30
local RARE={{max=25,shard={10978,1,1}},{max=30,shard={11084,1,1}},{max=35,shard={11138,1,1}},{max=40,shard={11139,1,1}},
 {max=45,shard={11177,1,1}},{max=50,shard={11178,1,1}},{max=55,shard={14343,1,1}},{max=65,shard={14344,1,1}}}
local EPIC={{max=45,shard={11177,2,4}},{max=50,shard={11178,2,4}},{max=55,shard={14343,2,4}},{max=65,shard={20725,1,1}}}
local NOT_DISENCHANTABLE={[11287]=true,[11288]=true,[11289]=true,[11290]=true} -- magic/mystic wands
local WEAPON,ARMOR=2,4

local function band(list,ilvl) for _,b in ipairs(list) do if ilvl<=b.max then return b end end end
local function yield(spec,chance) local avg=(spec[2]+spec[3])/2;return {itemID=spec[1],min=spec[2],max=spec[3],chance=chance,avg=avg,expected=chance*avg} end

-- Item facts needed to pick a bracket. nil while the item is not cached.
function M:DisenchantMeta(item)
 local info=C_Item and C_Item.GetItemInfo or GetItemInfo
 if not info or not item then return end
 local ok,name,link,quality,ilvl,_,_,_,_,equip,_,sell,classID,_,bind=pcall(info,item)
 if not ok or not name then return end
 local id=tonumber(type(item)=='number' and item or (type(link)=='string' and link:match('item:(%d+)')) or (type(item)=='string' and item:match('item:(%d+)')))
 if not classID then
  local instant=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
  if instant then local ok2,_,_,_,_,_,c=pcall(instant,item);if ok2 then classID=c end end
 end
 return {itemID=id,name=name,link=link,quality=tonumber(quality) or 0,ilvl=math.max(1,tonumber(ilvl) or 1),classID=classID,
  sell=tonumber(sell) and sell>0 and sell or nil,bind=bind,equip=equip}
end
function M:CanDisenchant(meta)
 return meta and meta.quality>=2 and meta.quality<=4 and (meta.classID==WEAPON or meta.classID==ARMOR)
  and not NOT_DISENCHANTABLE[meta.itemID or 0] and true or false
end
function M:DisenchantBracket(meta)
 return meta.quality..':'..(meta.classID==WEAPON and 'w' or 'a')..':'..math.floor((meta.ilvl-1)/5)
end
-- Built-in table for one item: { {itemID,chance,avg,expected,min,max}, ... }
function M:DisenchantTable(meta)
 if not self:CanDisenchant(meta) then return end
 local list
 if meta.quality==2 then
  local b=band(UNCOMMON,meta.ilvl);if not b then return end
  local dust,ess,shard=0.75,0.20,0.05
  if b.chances then dust,ess,shard=b.chances[1],b.chances[2],b.chances[3] end
  if not b.shard then dust,ess,shard=0.80,0.20,0 end
  local weapon=meta.classID==WEAPON
  if weapon then dust,ess=ess,dust end
  local essence=b.essence
  if weapon and meta.ilvl>=FOREVER_WEAPON_ESSENCE.min and meta.ilvl<=FOREVER_WEAPON_ESSENCE.max then essence=FOREVER_WEAPON_ESSENCE.essence end
  list={yield(b.dust,dust),yield(essence,ess)}
  if b.shard then list[3]=yield(b.shard,shard) end
 else
  local b=band(meta.quality==3 and RARE or EPIC,meta.ilvl);if not b then return end
  list={yield(b.shard,1)}
 end
 return list
end
-- Expected materials per disenchant: the table blended with your recorded casts.
function M:DisenchantYields(meta)
 local base=self:DisenchantTable(meta);if not base then return end
 local log=self.root and type(self.root.disenchantLog)=='table' and self.root.disenchantLog[self:DisenchantBracket(meta)]
 local n=log and tonumber(log.n) or 0
 if n<1 then return base,0 end
 local out,seen={},{}
 for _,y in ipairs(base) do
  local got=tonumber(log.mats[y.itemID]) or 0;seen[y.itemID]=true
  local e={itemID=y.itemID,chance=y.chance,avg=y.avg,min=y.min,max=y.max}
  e.expected=(y.expected*LEARN_WEIGHT+got)/(LEARN_WEIGHT+n);out[#out+1]=e
 end
 for id,got in pairs(log.mats) do if not seen[id] and tonumber(got) then
  out[#out+1]={itemID=id,expected=got/(LEARN_WEIGHT+n)}
 end end
 return out,n
end

local function matName(self,id)
 local info=C_Item and C_Item.GetItemInfo or GetItemInfo
 local ok,name=pcall(info or function() end,id)
 return ok and name or self.disenchantMats[id] or ('Item '..id)
end
-- Disenchant vs vendor vs auction for one item (link or itemID).
-- Returns nil when the item is not cached; .canDisenchant=false for others.
function M:DisenchantAdvice(item)
 local meta=self:DisenchantMeta(item);if not meta then return end
 local cut=1-(self.db and self.db.settings.ahCut or 0.05)
 local maxAge=self.db and self.db.settings.maxDataAge or 7200
 local a={meta=meta,canDisenchant=self:CanDisenchant(meta),vendor=meta.sell,options={}}
 if meta.sell then a.options[#a.options+1]={kind='Vendor',value=meta.sell} end
 -- The item itself on the AH (exact suffix/level variant only).
 if meta.bind~=1 and meta.bind~=4 then
  local key=type(item)=='string' and self:LinkIdentity(item) or self:Key(meta.itemID)
  local p=key and self:PriceObservation(key)
  if p and self:Finite(p.floor,1,1e12) then
   a.auction=math.floor(p.floor*cut);a.auctionStale=time()-p.at>maxAge or p.unverified
   a.options[#a.options+1]={kind='Auction',value=a.auction,stale=a.auctionStale}
  end
 end
 if a.canDisenchant then
  local yields,learned=self:DisenchantYields(meta)
  if yields then
   local value,missing,stale=0,0,false;a.yields={};a.learned=learned
   for _,y in ipairs(yields) do
    local p=self:PriceObservation(self:Key(y.itemID))
    local row={itemID=y.itemID,name=matName(self,y.itemID),chance=y.chance,expected=y.expected,min=y.min,max=y.max}
    if p and self:Finite(p.floor,1,1e12) then
     row.unit=p.floor;row.value=p.floor*y.expected*cut;value=value+row.value
     if time()-p.at>maxAge or p.unverified then stale=true;row.stale=true end
    elseif y.expected>=0.02 then missing=missing+1 end
    a.yields[#a.yields+1]=row
   end
   a.missing=missing;a.deStale=stale
   if value>0 then
    a.disenchant=math.floor(value)
    a.options[#a.options+1]={kind='Disenchant',value=a.disenchant,stale=stale,partial=missing>0}
   end
  end
 end
 table.sort(a.options,function(x,y) return x.value>y.value end)
 -- Not worth the cast: within 10% of vendor (or less) means vendor it.
 local margin=self.db and tonumber(self.db.settings.deVendorMargin) or 0.10
 a.deClose=a.disenchant and a.vendor and a.disenchant<=a.vendor*(1+margin) or false
 if a.deClose and a.options[1] and a.options[1].kind=='Disenchant' then
  for i,o in ipairs(a.options) do if o.kind=='Vendor' then table.remove(a.options,i);table.insert(a.options,1,o);break end end
 end
 a.best=a.options[1];a.second=a.options[2]
 return a
end

-- Tooltip -------------------------------------------------------------------
-- Shown while Shift is held: what the item disenchants into, each material's
-- chance and its expected share at current AH prices, the total, and the call.
function M:AppendDisenchantTooltip(tip,link)
 if not self.db or self.db.settings.tooltipDisenchant==false or not tip then return end
 if not (IsShiftKeyDown and IsShiftKeyDown()) then return end
 local a=self:DisenchantAdvice(link)
 if not a or not a.canDisenchant or not a.yields then return end
 local grey=function(s) return '|cff999999'..s..'|r' end
 tip:AddLine('Disenchants into:',.7,.4,1)
 for _,y in ipairs(a.yields) do
  local qty=y.min and (y.min==y.max and tostring(y.min) or (y.min..'-'..y.max)) or '?'
  local left='  '..y.name..(y.chance and (' '..math.floor(y.chance*100+0.5)..'% x'..qty) or '')
  local right
  if y.unit then
   right=self:Coins(y.value)..grey(' ('..self:Coins(y.unit)..' ea)')
   if y.stale then right=grey(self:Coins(y.value)..' old price') end
  else right=grey('no price') end
  tip:AddDoubleLine(left,right,.85,.85,.85,1,1,1)
 end
 if a.disenchant then
  local txt=self:Coins(a.disenchant)..(a.missing>0 and grey(' +?') or '')
  if a.deClose then txt='|cffff4040'..self:Coins(a.disenchant)..'|r'..(a.missing>0 and grey(' +?') or '') end
  tip:AddDoubleLine('Disenchant value',txt,1,.82,0,1,1,1)
 else
  tip:AddDoubleLine('Disenchant value',grey('no material prices - scan the AH'),1,.82,0,.6,.6,.6)
 end
 if a.best then
  local s
  if a.best.kind=='Vendor' and a.deClose then
   s='|cffff4040Vendor|r'..grey(' (disenchant within '..math.floor((tonumber(self.db.settings.deVendorMargin) or 0.1)*100+0.5)..'% of vendor)')
  else
   local more=a.second and a.best.value-a.second.value or 0
   local color=a.best.kind=='Disenchant' and '|cffb366ff' or a.best.kind=='Auction' and '|cff66ccff' or '|cffffd100'
   s=color..a.best.kind..'|r'..(more>0 and a.second and grey(' (+'..self:Coins(more)..' vs '..a.second.kind:lower()..')') or '')
  end
  tip:AddDoubleLine('Best',s,1,.82,0,1,1,1)
 end
 if (a.learned or 0)>0 then tip:AddLine(grey('  Adjusted by '..a.learned..' of your disenchants'),1,1,1) end
end
-- Re-draw the hovered tooltip when Shift goes down/up.
M:RegisterHandler('MODIFIER_STATE_CHANGED',function(self,_,key)
 if type(key)~='string' or not key:find('SHIFT') or not GameTooltip or not GameTooltip:IsShown() then return end
 if self.db and self.db.settings.tooltipDisenchant==false then return end
 local owner=GameTooltip.GetOwner and GameTooltip:GetOwner()
 if type(owner)~='table' then return end
 if owner.UpdateTooltip then pcall(owner.UpdateTooltip,owner)
 elseif owner.GetScript and owner.IsMouseOver and owner:IsMouseOver() then
  local fn=owner:GetScript('OnEnter');if fn then pcall(fn,owner) end
 end
end)

-- Bag check window ------------------------------------------------------------
function M:DisenchantBagRows()
 local out={};local get=C_Container and C_Container.GetContainerItemInfo
 local slots=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
 if not get or not slots then return out end
 for bag=0,4 do for slot=1,(slots(bag) or 0) do
  local info=get(bag,slot)
  local link=type(info)=='table' and info.hyperlink
  if link and not info.isLocked then
   local a=self:DisenchantAdvice(link)
   if a and a.canDisenchant then out[#out+1]={bag=bag,slot=slot,link=link,icon=info.iconFileID,advice=a} end
  end
 end end
 table.sort(out,function(x,y)
  local gx=x.advice.best and x.advice.best.kind=='Disenchant' and 1 or 0
  local gy=y.advice.best and y.advice.best.kind=='Disenchant' and 1 or 0
  if gx~=gy then return gx>gy end
  return (x.advice.best and x.advice.best.value or 0)>(y.advice.best and y.advice.best.value or 0)
 end)
 return out
end
-- Every disenchantable item in VoidMark's market database: buy on the AH at
-- the stored price, disenchant, sell the materials. Profitable ones first.
function M:DisenchantMarketRows()
 local out={};local maxAge=self.db.settings.maxDataAge;local loading=0
 local load=C_Item and C_Item.RequestLoadItemDataByID
 for key,m in pairs(self.db.market or {}) do
  local q=tonumber(m.quality)
  if type(m)=='table' and not m.archived and (q==nil or (q>=2 and q<=4)) then
   local item=type(m.itemLink)=='string' and m.itemLink or m.itemID
   local p=self:PriceObservation(key)
   if p and self:Finite(p.floor,1,1e12) then
    local a=self:DisenchantAdvice(item)
    if not a and self:Finite(m.itemID,1,1e9) then loading=loading+1;if load then pcall(load,m.itemID) end end
    if a and a.canDisenchant and a.disenchant then
     a.buy=p.floor;a.buyStale=time()-p.at>maxAge or p.unverified;a.profit=a.disenchant-p.floor
     out[#out+1]={marketKey=key,link=type(m.itemLink)=='string' and m.itemLink or a.meta.link,icon=m.texture,advice=a,name=m.name or a.meta.name}
    end
   end
  end
 end
 out.loading=loading
 table.sort(out,function(x,y) if x.advice.profit~=y.advice.profit then return x.advice.profit>y.advice.profit end return tostring(x.marketKey)<tostring(y.marketKey) end)
 return out
end
local ROWS=13
local HEAD={bags={'Item','Vendor','Auction','Disenchant','Best'},market={'Item (AH)','Buy price','Vendor','Disenchant','Profit'}}
function M:ShowDisenchantWindow(mode)
 local f=self.disenchantWindow
 if not f then
  local function label(p,t,x,y,w,font) local s=p:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlight');s:SetPoint('TOPLEFT',x,y);if w then s:SetWidth(w) end;s:SetJustifyH('LEFT');s:SetText(t or '');return s end
  local function button(p,t,x,y,w,fn) local b=CreateFrame('Button',nil,p,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,24);b:SetText(t);b:SetScript('OnClick',fn);return b end
  f=CreateFrame('Frame','VoidMarkMarketDisenchantFrame',UIParent,'BackdropTemplate');self.disenchantWindow=f
  f:SetSize(700,470);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetMovable(true);f:EnableMouse(true);f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart',function(w) w:StartMoving() end);f:SetScript('OnDragStop',function(w) w:StopMovingOrSizing() end)
  if f.SetBackdrop then
   f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=14})
   f:SetBackdropColor(0.035,0.026,0.065,0.98);f:SetBackdropBorderColor(0.48,0.25,0.75,1)
  end
  if UISpecialFrames then table.insert(UISpecialFrames,'VoidMarkMarketDisenchantFrame') end
  label(f,'DISENCHANT OR VENDOR?',18,-14,300,'GameFontNormalLarge')
  f.bagsTab=button(f,'My bags',300,-11,100,function() f.mode='bags';f.offset=0;self:RenderDisenchantWindow() end)
  f.marketTab=button(f,'AH items',404,-11,100,function() f.mode='market';f.offset=0;self:RenderDisenchantWindow() end)
  button(f,'Refresh',508,-11,90,function() self:RenderDisenchantWindow() end)
  button(f,'Close',604,-11,80,function() f:Hide() end)
  f.summary=label(f,'',18,-44,664,'GameFontHighlightSmall')
  local cols={{'Item',46},{'Vendor',290},{'Auction',380},{'Disenchant',470},{'Best',570}}
  f.heads={};for i,c in ipairs(cols) do f.heads[i]=label(f,c[1],c[2],-74,100,'GameFontNormalSmall') end
  f.rows={}
  for i=1,ROWS do
   local r=CreateFrame('Button',nil,f);r:SetPoint('TOPLEFT',14,-92-(i-1)*27);r:SetSize(672,26)
   r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
   r.icon=r:CreateTexture(nil,'ARTWORK');r.icon:SetPoint('LEFT',6,0);r.icon:SetSize(22,22)
   r.c={label(r,'',34,-7,240),label(r,'',276,-7,88),label(r,'',366,-7,88),label(r,'',456,-7,98),label(r,'',556,-7,110)}
   r:SetScript('OnEnter',function(b) if b.link and GameTooltip then GameTooltip:SetOwner(b,'ANCHOR_RIGHT');GameTooltip:SetHyperlink(b.link);GameTooltip:Show() end end)
   r:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
   f.rows[i]=r
  end
  f:EnableMouseWheel(true)
  f:SetScript('OnMouseWheel',function(_,d) f.offset=math.max(0,math.min(math.max(0,#(f.data or {})-ROWS),(f.offset or 0)-(d>0 and 3 or -3)));self:RenderDisenchantWindow(true) end)
  f.empty=label(f,'',18,-200,664,'GameFontHighlightLarge');f.empty:SetJustifyH('CENTER')
  f.foot=label(f,'Prices after the '..math.floor((self.db.settings.ahCut or 0.05)*100+0.5)..'% AH cut. Disenchant value is the average over many disenchants. Red = disenchant within 10% of vendor, so vendor it. Hover a row and hold Shift for the materials.',18,-446,664,'GameFontHighlightSmall')
 end
 f.mode=mode or f.mode or 'bags';f.offset=0;f:Show();self:RenderDisenchantWindow()
end
function M:RenderDisenchantWindow(keep)
 local f=self.disenchantWindow;if not f or not f:IsShown() then return end
 local market=f.mode=='market'
 for i,h in ipairs(f.heads) do h:SetText(HEAD[market and 'market' or 'bags'][i]) end
 f.bagsTab:SetEnabled(market);f.marketTab:SetEnabled(not market)
 if not keep then f.data=market and self:DisenchantMarketRows() or self:DisenchantBagRows() end
 if market then return self:RenderDisenchantMarket(f) end
 local data=f.data;local extra,count=0,0
 for _,r in ipairs(data) do local a=r.advice
  if a.best and a.best.kind=='Disenchant' then count=count+1;extra=extra+a.best.value-(a.vendor or 0) end
 end
 f.summary:SetText(#data==0 and '' or (count>0 and ('Disenchant '..count..' of '..#data..' items: about '..self:Coins(extra)..' more than vendoring them.')
  or 'Nothing in your bags is worth more disenchanted right now.'))
 f.empty:SetText(#data==0 and 'No disenchantable gear (green, blue or purple weapons and armor) in your bags.' or '')
 local off=f.offset or 0
 for i,row in ipairs(f.rows) do
  local r=data[i+off];row:SetShown(r~=nil);row.link=r and r.link
  if r then
   local a=r.advice;row.icon:SetTexture(r.icon)
   row.c[1]:SetText(r.link)
   row.c[2]:SetText(a.vendor and self:Coins(a.vendor) or '--')
   row.c[3]:SetText(a.auction and (a.auctionStale and '|cff999999'..self:Coins(a.auction)..'|r' or self:Coins(a.auction)) or '--')
   row.c[4]:SetText(a.disenchant and ((a.deClose and '|cffff4040' or a.deStale and '|cff999999' or '')..self:Coins(a.disenchant)..((a.deClose or a.deStale) and '|r' or '')..(a.missing>0 and '|cff999999 +?|r' or '')) or '|cff999999no prices|r')
   local best=a.best and a.best.kind or '--'
   local color=best=='Disenchant' and '|cffb366ff' or best=='Auction' and '|cff66ccff' or a.deClose and '|cffff4040' or '|cffffd100'
   row.c[5]:SetText(color..best..'|r')
  end
 end
end

function M:RenderDisenchantMarket(f)
 local data=f.data;local good=0
 for _,r in ipairs(data) do if r.advice.profit>0 then good=good+1 end end
 f.summary:SetText(#data==0 and '' or (good>0 and (good..' of '..#data..' disenchantable items in the VoidMark database are worth buying to disenchant (at the stored prices; check live before buying).')
  or ('None of the '..#data..' disenchantable items in the VoidMark database pay to disenchant at the stored prices.'))
  ..((data.loading or 0)>0 and ('  '..data.loading..' items still loading - press Refresh.') or ''))
 f.empty:SetText(#data==0 and ((data.loading or 0)>0 and 'Item data is still loading - press Refresh.' or 'No disenchantable items with prices in the VoidMark database yet. Run a full AH scan.') or '')
 local off=f.offset or 0
 local grey=function(s,on) return on and ('|cff999999'..s..'|r') or s end
 for i,row in ipairs(f.rows) do
  local r=data[i+off];row:SetShown(r~=nil);row.link=r and r.link
  if r then
   local a=r.advice;row.icon:SetTexture(r.icon or (GetItemIcon and GetItemIcon(a.meta.itemID)))
   row.c[1]:SetText(r.link or r.name)
   row.c[2]:SetText(grey(self:Coins(a.buy),a.buyStale))
   row.c[3]:SetText(a.vendor and self:Coins(a.vendor) or '--')
   row.c[4]:SetText(grey(self:Coins(a.disenchant),a.deStale)..(a.missing>0 and '|cff999999 +?|r' or ''))
   row.c[5]:SetText((a.profit>0 and '|cff66ff66' or '|cffff5555')..self:Coins(a.profit)..'|r')
  end
 end
end

-- Learning from your own disenchants ------------------------------------------
-- SENT (target = item name) -> SUCCEEDED -> the next loot window of only
-- enchanting materials within 6 s is that disenchant's result.
local pending
local function findBagLink(name)
 local get=C_Container and C_Container.GetContainerItemInfo
 local slots=C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
 if not (get and slots and name) then return end
 for bag=0,4 do for slot=1,(slots(bag) or 0) do
  local info=get(bag,slot);local link=type(info)=='table' and info.hyperlink
  if link and link:match('|h%[(.-)%]|h')==name then return link end
 end end
end
function M:RecordDisenchant(meta,mats)
 if self.persistenceBlocked or not self.root or not self:CanDisenchant(meta) then return false end
 local n=0;for id,q in pairs(mats) do if not self.disenchantMats[id] or not self:Finite(q,1,50) then return false end;n=n+1 end
 if n==0 then return false end
 self.root.disenchantLog=type(self.root.disenchantLog)=='table' and self.root.disenchantLog or {}
 local key=self:DisenchantBracket(meta)
 local rec=self.root.disenchantLog[key]
 if type(rec)~='table' or type(rec.mats)~='table' then rec={n=0,mats={}};self.root.disenchantLog[key]=rec end
 rec.n=(tonumber(rec.n) or 0)+1;rec.last=time()
 for id,q in pairs(mats) do rec.mats[id]=(tonumber(rec.mats[id]) or 0)+q end
 return true
end
M:RegisterHandler('UNIT_SPELLCAST_SENT',function(self,_,unit,target,castGUID,spellID)
 if unit~='player' or tonumber(spellID)~=DISENCHANT_SPELL then return end
 local link=findBagLink(target)
 pending=link and {link=link,guid=castGUID,t=GetTime()} or nil
end)
M:RegisterHandler('UNIT_SPELLCAST_SUCCEEDED',function(self,_,unit,castGUID,spellID)
 if unit~='player' or tonumber(spellID)~=DISENCHANT_SPELL or not pending then return end
 if pending.guid==nil or pending.guid==castGUID then pending.done=GetTime() end
end)
M:RegisterHandler('UNIT_SPELLCAST_FAILED',function(self,_,unit,castGUID,spellID) if unit=='player' and tonumber(spellID)==DISENCHANT_SPELL then pending=nil end end)
M:RegisterHandler('UNIT_SPELLCAST_INTERRUPTED',function(self,_,unit,castGUID,spellID) if unit=='player' and tonumber(spellID)==DISENCHANT_SPELL then pending=nil end end)
M:RegisterHandler('LOOT_OPENED',function(self)
 local p=pending;if not p or not p.done or GetTime()-p.done>6 then return end
 pending=nil
 if not (GetNumLootItems and GetLootSlotLink and GetLootSlotInfo) then return end
 local mats={}
 for i=1,GetNumLootItems() do
  local link=GetLootSlotLink(i);local id=tonumber(type(link)=='string' and link:match('item:(%d+)'))
  local _,_,qty=GetLootSlotInfo(i)
  if not id or not self.disenchantMats[id] then return end -- not a disenchant loot window
  mats[id]=(mats[id] or 0)+(tonumber(qty) or 1)
 end
 local meta=self:DisenchantMeta(p.link)
 if meta then self:RecordDisenchant(meta,mats) end
end)
