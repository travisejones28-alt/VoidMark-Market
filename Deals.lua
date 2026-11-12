local _,M=...
-- Flipping helpers for the Shopping tab (1.14.0).
--  * Search terms in shopping lists ("of the Monkey"): searching a list also
--    runs each term as a live Auction House name search and merges the results.
--  * "Vs Avg" on every result: the lowest price against that exact item's own
--    30-day history. Random-suffix items are their own market (Boots of the
--    Monkey and Boots of the Bear never share a price).
-- Terms are kept on this character only; item entries still sync as before.
local MAX_TERMS,MIN_SAMPLES=30,2
-- Term format (like Auctionator's extended search, in plain words):
--   [armor] [slot]: [text] [max 75s] [lvl 15+ | lvl 15-30]
--   "leather: agility max 50s", "cloth: intellect lvl 15+", "mail head: max 75s"
-- Armor/slot are checked on the item (Armor class 4). With no text, armor is
-- required and the AH is asked by category instead of by name.
local ARMOR={cloth=1,leather=2,mail=3,plate=4}
local SLOT={head={'INVTYPE_HEAD'},shoulder={'INVTYPE_SHOULDER'},shoulders={'INVTYPE_SHOULDER'},
 chest={'INVTYPE_CHEST','INVTYPE_ROBE'},waist={'INVTYPE_WAIST'},belt={'INVTYPE_WAIST'},legs={'INVTYPE_LEGS'},
 feet={'INVTYPE_FEET'},boots={'INVTYPE_FEET'},wrist={'INVTYPE_WRIST'},bracers={'INVTYPE_WRIST'},
 hands={'INVTYPE_HAND'},gloves={'INVTYPE_HAND'},back={'INVTYPE_CLOAK'},cloak={'INVTYPE_CLOAK'}}
local INVTYPE_ENUM={INVTYPE_HEAD=1,INVTYPE_SHOULDER=3,INVTYPE_CHEST=5,INVTYPE_WAIST=6,INVTYPE_LEGS=7,
 INVTYPE_FEET=8,INVTYPE_WRIST=9,INVTYPE_HAND=10,INVTYPE_CLOAK=16,INVTYPE_ROBE=20}
-- Azmork's list (one list for everything).
M.FLIP_STARTER={'cloth: magic','leather: agility max 50s','leather: monkey','mail: bear','cloth: sorcerer',
 'cloth: intellect lvl 15+','leather: tiger','leather head: max 75s','mail: strength','mail head: max 75s',
 'cloth: healing max 75s','cloth: physician max 75s'}
-- 1.14.0 starter terms, replaced by /vmm flipstarter.
M.OLD_FLIP_STARTER={'leather: of Agility','leather: of the Monkey','leather: of the Tiger',
 'cloth: of Healing','cloth: of Intellect','cloth: of the Sorcerer','cloth: of the Physician','cloth: of Magic',
 'mail: of the Bear','mail: of the Tiger','mail: of Strength'}
-- "75s", "1g", "1g25s", "50c", "75" (silver) -> copper
function M:ParseMoneyText(t)
 t=tostring(t or ''):lower():gsub('%s','')
 if t:match('^%d+$') then return tonumber(t)*100 end
 local total,any=0,false
 for n,u in t:gmatch('(%d+)([gsc])') do any=true;total=total+tonumber(n)*(u=='g' and 10000 or u=='s' and 100 or 1) end
 if not any or t:gsub('%d+[gsc]','')~='' then return nil end
 return total>0 and total or nil
end
-- Returns search text, armor subclass, and the full spec.
function M:ParseShopTerm(term)
 term=tostring(term or '')
 local spec={}
 local head,rest=term:match('^%s*([%a ]-)%s*:%s*(.-)%s*$')
 if head then
  local ok=true
  for w in head:lower():gmatch('%a+') do
   if ARMOR[w] and not spec.armor then spec.armor=ARMOR[w]
   elseif SLOT[w] and not spec.slot then spec.slot=SLOT[w]
   else ok=false end
  end
  if ok and (spec.armor or spec.slot) then term=rest else spec={} end
 end
 term=' '..term..' '
 term=term:gsub('%s[Mm][Aa][Xx]%s+(%S+)%s',function(v) spec.max=self:ParseMoneyText(v);return ' ' end)
 term=term:gsub('%s[Ll][Vv][Ll]%s+(%d+)%s*%-%s*(%d+)%s',function(a,b) spec.minLevel,spec.maxLevel=tonumber(a),tonumber(b);return ' ' end)
 term=term:gsub('%s[Ll][Vv][Ll]%s+(%d+)%+%s',function(a) spec.minLevel=tonumber(a);return ' ' end)
 term=term:gsub('%s[Ll][Vv][Ll]%s+(%d+)%-%s',function(a) spec.maxLevel=tonumber(a);return ' ' end)
 spec.text=term:match('^%s*(.-)%s*$')
 if spec.minLevel and spec.maxLevel and spec.minLevel>spec.maxLevel then spec.minLevel,spec.maxLevel=spec.maxLevel,spec.minLevel end
 return spec.text,spec.armor,spec
end
-- A term is usable when it has text, or an armor type to search by category.
function M:ShopTermValid(term)
 local text,armor=self:ParseShopTerm(term)
 return #text>=2 or armor~=nil
end
local function itemMatches(itemID,spec)
 if not spec.armor and not spec.slot then return true end
 local info=(C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
 if not info then return true end
 local _,_,_,equip,_,classID,subID=info(itemID)
 if classID==nil then return true end -- unknown to the client yet: keep it
 if spec.armor and not (classID==4 and subID==spec.armor) then return false end
 if spec.slot then
  local hit=false;for _,e in ipairs(spec.slot) do if equip==e then hit=true end end
  if not hit then return false end
 end
 return true
end
M.ShopItemMatchesTerm=itemMatches
function M:FlipMaxBuy()
 local v=tonumber(self.db.settings.flipMaxBuy)
 return (v and v>=1 and v<=1e10) and math.floor(v) or nil
end
-- Required-level range for Shopping searches (0 = no limit on that end).
function M:ShopLevelRange()
 local lo,hi=tonumber(self.db.settings.shopMinLevel),tonumber(self.db.settings.shopMaxLevel)
 lo=(lo and lo>=1 and lo<=80) and math.floor(lo) or nil
 hi=(hi and hi>=1 and hi<=80) and math.floor(hi) or nil
 if lo and hi and lo>hi then lo,hi=hi,lo end
 return lo,hi
end
function M:SetShopLevelRange(lo,hi)
 if self.persistenceBlocked then return end
 lo,hi=tonumber(lo),tonumber(hi)
 self.db.settings.shopMinLevel=(lo and lo>=1 and lo<=80) and math.floor(lo) or 0
 self.db.settings.shopMaxLevel=(hi and hi>=1 and hi<=80) and math.floor(hi) or 0
 self:RefreshUI()
end
function M:ApplyLevelQuery(q,spec)
 local lo,hi=self:ShopLevelRange()
 if spec and (spec.minLevel or spec.maxLevel) then lo,hi=spec.minLevel,spec.maxLevel end
 q.minLevel=lo;q.maxLevel=hi;return q
end
-- The AH query already limits level; this double-checks when the item is
-- cached. Items the client doesn't know yet are kept.
function M:LevelAllowed(itemID,spec)
 local lo,hi=self:ShopLevelRange()
 if spec and (spec.minLevel or spec.maxLevel) then lo,hi=spec.minLevel,spec.maxLevel end
 if not lo and not hi then return true end
 if not GetItemInfo then return true end
 local ok,_,_,_,_,req=pcall(GetItemInfo,itemID)
 req=ok and tonumber(req) or nil
 if not req then return true end
 return not (lo and req<lo) and not (hi and req>hi)
end
function M:LevelRangeText()
 local lo,hi=self:ShopLevelRange()
 if lo and hi then return 'level '..lo..'-'..hi elseif lo then return 'level '..lo..'+' elseif hi then return 'level '..hi..' or lower' end
end

-- Adds the starter terms to the main Shopping list (one list for everything).
function M:AddFlipStarter()
 local added=0
 local book=self:ShopTermBook('Shopping')
 if book then for _,old in ipairs(self.OLD_FLIP_STARTER) do for i=#book,1,-1 do if book[i]==old then table.remove(book,i) end end end end
 for _,t in ipairs(self.FLIP_STARTER) do if self:AddShopTerm('Shopping',t) then added=added+1 end end
 return added
end

-- Search terms -------------------------------------------------------------
local function trim(s) return (tostring(s or ''):gsub('[%c|]',' '):match('^%s*(.-)%s*$')) end
function M:ShopTermBook(list,create)
 if type(list)~='string' or list=='' then return nil end
 if type(self.db.shopTerms)~='table' then if not create then return nil end;self.db.shopTerms={} end
 local t=self.db.shopTerms[list]
 if type(t)~='table' then if not create then return nil end;t={};self.db.shopTerms[list]=t end
 return t
end
function M:ShopTerms(list)
 local out={}
 for _,term in ipairs(self:ShopTermBook(list) or {}) do if type(term)=='string' and term~='' then out[#out+1]=term end end
 return out
end
function M:AddShopTerm(list,text)
 if self.persistenceBlocked then return false,'Database read-only' end
 text=trim(text)
 if #text<2 or #text>40 then return false,'Search terms must be 2-40 characters' end
 if not self:ShopTermValid(text) then return false,'Add search text, or an armor type like "leather head: max 75s"' end
 local book=self:ShopTermBook(list,true);if not book then return false,'Open a shopping list first' end
 for _,t in ipairs(book) do if type(t)=='string' and t:lower()==text:lower() then return false,'"'..text..'" is already in '..list end end
 if #book>=MAX_TERMS then return false,MAX_TERMS..' search terms per list maximum' end
 book[#book+1]=text;self:RefreshUI();return true
end
function M:RemoveShopTerm(list,text)
 local book=self:ShopTermBook(list);if not book then return false end
 for i=#book,1,-1 do if book[i]==text then table.remove(book,i) end end
 if #book==0 and self.db.shopTerms then self.db.shopTerms[list]=nil end
 if self.termRows then
  for i=#self.termRows,1,-1 do if self.termRows[i].term==text then table.remove(self.termRows,i) end end
 end
 self:RefreshUI();return true
end

-- Auctionator shopping list export: "List Name^term^term" (one list per line).
-- Advanced terms ("of the Monkey;;10;30") keep only the text before the first ';'.
function M:ImportAuctionatorLists(raw)
 if self.persistenceBlocked then return false,'Database read-only' end
 if type(raw)~='string' or #raw>35000 then return false,'Invalid import' end
 local lists,terms=0,0
 for line in (raw:gsub('\r\n','\n')..'\n'):gmatch('(.-)\n') do
  if line:find('^',1,true) then
   local parts={};for p in (line..'^'):gmatch('(.-)%^') do parts[#parts+1]=p end
   local name=trim(parts[1]):sub(1,24)
   if name~='' and self:ListBook(name,true) then
    lists=lists+1
    for i=2,#parts do
     local term=trim((parts[i]:match('^([^;]*)') or ''):gsub('^"(.*)"$','%1'))
     if self:AddShopTerm(name,term) then terms=terms+1 end
    end
   end
  end
 end
 if lists==0 then return false,'Nothing to import. Paste an Auctionator export like: Flips^of the Monkey^of the Tiger' end
 return true,('Imported %d search term%s into %d list%s'):format(terms,terms==1 and '' or 's',lists,lists==1 and '' or 's')
end

-- Term sweep --------------------------------------------------------------
-- Runs each term through the AH queue one after another; results are merged
-- by item (lowest price wins) into self.termRows, shown with the list.
function M:SearchShopTerms(list,onlyTerm)
 local terms=self:ShopTerms(list)
 if onlyTerm then terms={onlyTerm} end
 if #terms==0 or not self.ahOpen or not self:CanUseAuctionHouse() then return false end
 if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then self:Print('Live browse unavailable');return false end
 local run={list=list,total=0,done=0,found=0,rows={},byKey={}}
 self.termSearch=run;self.termRows={}
 for _,term in ipairs(terms) do
  local text,armor,spec=self:ParseShopTerm(term)
  local classFilters={}
  if text=='' and armor then
   -- Category search: Armor > subclass (> slot when it is one inventory type).
   local inv=spec.slot and #spec.slot==1 and INVTYPE_ENUM[spec.slot[1]]
   classFilters[1]={classID=4,subClassID=armor,inventoryType=inv or nil}
  end
  local queued=self:QueueRequest({id='browse-term:'..term:lower(),kind='browse',priority=40,
   query=self:ApplyLevelQuery({searchString=text,sorts={},filters={},itemClassFilters=classFilters},spec),
   done=function()
    if self.termSearch~=run then return end
    local result=C_AuctionHouse.GetBrowseResults() or {}
    for i=1,math.min(300,#result) do
     local b=result[i];local k=b.itemKey
     local key=k and self:Key(k.itemID,k.itemSuffix,k.itemLevel,k.battlePetSpeciesID)
     if key and self:Finite(b.minPrice,1,1e12) then
      self:RecordLiveFloor(key,b.minPrice,b.totalQuantity)
      local old=run.byKey[key]
      local max=spec.max or self:FlipMaxBuy()
      if (not old or b.minPrice<old.floor) and itemMatches(k.itemID,spec) and not (max and b.minPrice>max) and self:LevelAllowed(k.itemID,spec) then
       local m=self.db.market[key];local info=C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(k)
       local row={marketKey=key,itemID=k.itemID,name=(info and info.itemName) or (m and m.name) or self:ItemName(k.itemID) or ('Item '..k.itemID),
        floor=b.minPrice,quantity=tonumber(b.totalQuantity),fair=m and m.fairValue or 0,
        confidence=m and m.confidence or 'Unknown',status='LIVE BROWSE',term=term}
       if not old then run.rows[#run.rows+1]=row;run.found=run.found+1 else for j,r in ipairs(run.rows) do if r==old then run.rows[j]=row end end end
       run.byKey[key]=row
      end
     end
    end
    run.done=run.done+1;self.termRows=run.rows
    if run.done>=run.total then run.finished=true
     self:Print(('Search terms: %d item%s found in %s'):format(run.found,run.found==1 and '' or 's',list)) end
    self:RefreshUI()
   end,
   fail=function()
    if self.termSearch~=run then return end
    run.done=run.done+1;run.failed=(run.failed or 0)+1
    if run.done>=run.total then run.finished=true end
    self:RefreshUI()
   end})
  if queued then run.total=run.total+1 end
 end
 if run.total==0 then self.termSearch=nil;return false end
 self:RefreshUI();return true
end
function M:TermSearchRunning()
 local r=self.termSearch;return r~=nil and not r.finished
end
function M:StopTermSearch()
 self.termSearch=nil
 local q=self.queue;if not q then return end
 for i=#q.waiting,1,-1 do
  local r=q.waiting[i]
  if type(r.id)=='string' and r.id:find('^browse%-term:') then table.remove(q.waiting,i);q.dedupe[r.id]=nil end
 end
end
function M:TermSearchStatus()
 local r=self.termSearch
 if r and not r.finished then return 'Searching terms in '..r.list..': '..r.done..' / '..r.total..' | Keep the AH open' end
end

-- Deal check --------------------------------------------------------------
function M:DealPercent()
 local p=tonumber(self.db.settings.dealPercent)
 return (p and p>=10 and p<=100) and math.floor(p) or 60
end
-- Reference price for one exact market: 30-day median of full scans, else the
-- model's fair value once it is trusted. Nil when there is no real history.
function M:DealReference(key)
 local m=key~=nil and self.db.market[key]
 if type(m)~='table' then return nil end
 local month=self:MarketWindow(m,30)
 if month and month.samples>=MIN_SAMPLES then return month.median,month.samples end
 if self:Finite(m.fairValue,1,1e12) and self:CanEstimateResale(m) then return math.floor(m.fairValue),month and month.samples or 0 end
end
-- Percent of the reference price the lowest listing costs (45 = 55% under).
function M:DealRatio(row)
 if type(row)~='table' or not self:Finite(row.floor,1,1e12) then return nil end
 local ref=self:DealReference(row.marketKey)
 if not ref then return nil end
 return math.floor(row.floor/ref*100+0.5),ref
end
function M:DealText(row)
 local pct=self:DealRatio(row)
 if not pct then return '|cff8f8f8f--|r' end
 if pct<=self:DealPercent() then return '|cff40ff40'..pct..'%|r' end
 if pct<100 then return '|cffffffff'..pct..'%|r' end
 return '|cffff8060'..pct..'%|r'
end
