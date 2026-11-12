local _,M=...
-- Auctionator-style live trading helpers (behavior reference: Auctionator 342,
-- Source_ModernAH shopping/selling/cancelling; independent implementation).
--  * Every complete live search records the competitor floor (incremental prices).
--  * Shopping lists can be searched live, item by item.
--  * Selling suggests lowest competitor minus a small undercut, posts whole
--    commodity quantities, remembers duration and moves to the next bag item.
--  * Cancelling checks every listing for undercuts and cancels one per click.
local LIVE_CAP,LIVE_DAYS=5000,7

-- Incremental live prices --------------------------------------------------
function M:LiveSeenBook()
 if type(self.db.liveSeen)~='table' then self.db.liveSeen={} end
 return self.db.liveSeen
end
function M:PruneLiveSeen()
 local t=self:LiveSeenBook();local cutoff=time()-LIVE_DAYS*86400;local keep={}
 for k,e in pairs(t) do
  if type(e)~='table' or not self:Finite(e.floor,1,1e12) or not self:Finite(e.at,cutoff,time()+60) then t[k]=nil
  else keep[#keep+1]={k,e.at} end
 end
 if #keep>LIVE_CAP then
  table.sort(keep,function(a,b) return a[2]<b[2] end)
  for i=1,#keep-math.floor(LIVE_CAP*0.8) do t[keep[i][1]]=nil end
  self.liveSeenCount=math.floor(LIVE_CAP*0.8)
 else self.liveSeenCount=#keep end
end
function M:RecordLiveFloor(key,floor,quantity)
 if self.persistenceBlocked or not self.db or key==nil or not self:Finite(floor,1,1e12) then return end
 local t=self:LiveSeenBook()
 if t[key]==nil then self.liveSeenCount=(self.liveSeenCount or 0)+1 end
 t[key]={floor=math.ceil(floor),quantity=self:Finite(quantity,1,1e9) and math.floor(quantity) or nil,at=time()}
 if self.RecordDailyLow then self:RecordDailyLow(key,floor) end
 if self.PublishLiveFloor then pcall(self.PublishLiveFloor,self,key,math.ceil(floor),time()) end
 if self.liveSeenCount>LIVE_CAP then self:PruneLiveSeen() end
end
function M:RecordSearchResult(result)
 if type(result)~='table' or not result.key or not result.rows or not result.rows[1] then return end
 local k=result.key;local key=self:Key(k.itemID,k.itemSuffix,k.itemLevel,k.battlePetSpeciesID)
 local qty=0;for _,r in ipairs(result.rows) do qty=qty+(tonumber(r.quantity) or 0) end
 self:RecordLiveFloor(key,result.rows[1].unit,qty)
end
-- A live observation newer than the stored one wins; history estimates stay.
function M:PriceObservation(key)
 local p=self:StoredPriceObservation(key)
 local l=self.db and type(self.db.liveSeen)=='table' and self.db.liveSeen[key]
 if type(l)~='table' or not self:Finite(l.floor,1,1e12) or not self:Finite(l.at,1,time()+60) then return p end
 if p and p.at>=l.at and not p.unverified then return p end
 return {floor=l.floor,at=l.at,quantity=l.quantity,fair=p and p.fair,confidence=p and p.confidence,developing=true,source='Live search'}
end

-- Shopping list live search -------------------------------------------------
local function marketFor(self,key,row)
 local k,id,s,l,p=self:ParseKey(key)
 if not k then return end
 return self.db.market[k] or {marketKey=k,itemID=id,itemSuffix=s,itemLevel=l,battlePetSpeciesID=p,name=row and row.name or ('Item '..id)}
end
-- onlyKey: search a single entry of the list (clicking an item in the lists panel).
function M:SearchShoppingList(onlyKey)
 if not self.ahOpen or not self:CanUseAuctionHouse() then self:Print('Open the Auction House to search a list');return false end
 local rows=self:GetWatchRows()
 if onlyKey~=nil then
  local one={};for _,r in ipairs(rows) do if r.marketKey==onlyKey then one[1]=r end end;rows=one
 end
 if #rows==0 then self:Print('This shopping list is empty');return false end
 local run={list=self.activeList,total=0,done=0,found=0,none=0,failed=0}
 self.listSearch=run;self.listEmpty=self.listEmpty or {}
 local function finish()
  run.done=run.done+1
  if run.live and run.done>=run.total and self.listSearch==run then
   run.finished=true
   self:Print(('List search: %d found, %d not listed%s'):format(run.found,run.none,run.failed>0 and (', '..run.failed..' failed') or ''))
  end
  self:RefreshUI()
 end
 for _,row in ipairs(rows) do
  local m=marketFor(self,row.marketKey,row)
  local key=row.marketKey
  if m then
   local queued=self:Search(m,20,function(result)
    if self.listSearch~=run then return end
    if result.rows[1] then run.found=run.found+1;self.listEmpty[key]=nil
    else run.none=run.none+1;self.listEmpty[key]=time() end
    finish()
   end,function() if self.listSearch==run and run.live then run.failed=run.failed+1;finish() end end,
   function() return self.listSearch==run end)
   if queued then run.total=run.total+1 end
  end
 end
 run.live=true
 if run.total==0 then self.listSearch=nil;self:Print('No list items could be searched yet; try again in a moment');return false end
 self:RefreshUI();return true
end
function M:ListSearchStatus()
 local r=self.listSearch
 if r and not r.finished then return 'Searching list '..r.list..': '..r.done..' / '..r.total..' | Keep the AH open' end
end

-- Selling -------------------------------------------------------------------
function M:PostDuration()
 local d=tonumber(self.db.settings.postDuration)
 return (d==1 or d==2 or d==3) and d or 3
end
-- Forever's AH refuses regular-item prices with copper (Database Error);
-- commodities accept copper. Items post in whole silver.
function M:WholeSilver(unit,up)
 unit=math.floor(unit)
 local s=up and math.ceil(unit/100)*100 or math.floor(unit/100)*100
 return math.max(100,s)
end
function M:SuggestPostUnit(row,floor,commodity)
 local unit
 if self:Finite(floor,1,1e12) then
  local cut=tonumber(self.db.settings.sellUndercut) or 1
  cut=self:Finite(cut,0,1e9) and math.floor(cut) or 1
  unit=math.max(1,math.floor(floor)-cut)
 elseif row and self:Finite(row.price,1,1e12) then unit=math.floor(row.price) end
 -- Items: highest whole silver below the lowest listing (16s -> 15s).
 if unit and commodity==false then unit=self:WholeSilver(unit) end
 local min=row and row.marketKey and self.db.sellFloors and self.db.sellFloors[row.marketKey]
 local why='minimum'
 if not self:Finite(min,1,1e12) then min=nil end
 -- Never below what you paid (Flip Ledger) plus the AH cut, unless turned off.
 local paid=self.PaidFloor and self:PaidFloor(row)
 if paid and (not min or paid>min) then min=paid;why='paid' end
 if unit and min and unit<min then
  min=math.ceil(min); if commodity==false then min=self:WholeSilver(min,true) end
  return min,true,why
 end
 return unit
end
function M:FormatGoldInput(copper) return ('%0.4f'):format(copper/10000) end
-- Post price lives in gold/silver/copper boxes (SellScreen); these helpers
-- keep the selling logic independent of the widgets.
function M:SetPostPrice(copper)
 if not self.postGold then return end
 if not copper then self.postGold:SetText('');self.postSilver:SetText('');self.postCopper:SetText('');return end
 copper=math.floor(copper)
 self.postGold:SetText(tostring(math.floor(copper/10000)));self.postSilver:SetText(tostring(math.floor(copper/100)%100));self.postCopper:SetText(tostring(copper%100))
end
function M:PostPriceEmpty()
 return not self.postGold or (self.postGold:GetText()=='' and self.postSilver:GetText()=='' and self.postCopper:GetText()=='')
end
function M:GetPostPrice()
 if self:PostPriceEmpty() then return nil end
 local function part(e,max) local t=e:GetText();if t=='' then return 0 end;local n=tonumber(t);if not n or n<0 or n%1~=0 or (max and n>max) then return nil end;return n end
 local g,s,c=part(self.postGold),part(self.postSilver,99),part(self.postCopper,99)
 if not g or not s or not c then return nil end
 return g*10000+s*100+c
end
-- Selecting a bag item fills quantity and starts the live price check.
function M:SelectSellRow(row,check)
 if not row then return end
 local changed=self.selectedRow~=row
 self.selectedRow=row
 if changed then
  self.postQuote=nil;self.sellListPage=1
  self:SetPostPrice(nil)
  if self.postQty then self.postQty:SetText(tostring(math.max(1,tonumber(row.quantity) or 1,self:BagCount(row.marketKey,row.itemID,row.name)))) end
 end
 if check and changed and self.ahOpen and self.view=='selling' then self:CheckPost(row) end
 self:RefreshUI()
end
function M:AfterPostRefresh(rows)
 local next=self.selectAfterRefresh;self.selectAfterRefresh=nil
 if not next or self.view~='selling' then return end
 local tiles=self.SellTiles and self:SellTiles(rows) or rows
 if #tiles==0 then return end
 self.selectedRow=nil
 local t=tiles[math.min(next,#tiles)]
 -- Select now, check the price a moment later (bags settle after a post).
 self:SelectSellRow(t.row or t,false)
 self.sellCheckAt=GetTime()+0.75;self.sellCheckRow=t.row or t
end
function M:BagCount(key,itemID,name)
 local n=0
 for _,r in ipairs(self.sellingRows or {}) do
  if ((key~=nil and r.marketKey==key) or (key==nil and r.itemID==itemID)) and (not name or not r.name or r.name==name) then n=n+(tonumber(r.quantity) or 0) end
 end
 return n
end
function M:SellTick()
 local q=self.postQuote
 if q and not q.at and q.deadline and GetTime()>=q.deadline and self.UseScanPrice then self:UseScanPrice(q,'no reply in 10 seconds') end
 if self.sellCheckAt and GetTime()>=self.sellCheckAt then
  local row=self.sellCheckRow;self.sellCheckAt=nil;self.sellCheckRow=nil
  if row and row==self.selectedRow and self.ahOpen and self.view=='selling' then self:CheckPost(row);self:RefreshUI() end
 end
end
-- Once per post (the post click and the created event can both report it).
function M:RecordPostHistory(posted)
 if type(posted)~='table' or posted.postHistoryRecorded or posted.marketKey==nil or self.persistenceBlocked or not posted.postedUnit then return end
 posted.postHistoryRecorded=true
 self.db.postHistory=type(self.db.postHistory)=='table' and self.db.postHistory or {}
 local h=self.db.postHistory[posted.marketKey] or {};self.db.postHistory[posted.marketKey]=h
 table.insert(h,1,{at=time(),unit=posted.postedUnit,quantity=posted.postedQuantity,duration=posted.postedDuration})
 while #h>20 do table.remove(h) end
end
M:RegisterHandler('AUCTION_HOUSE_AUCTION_CREATED',function(self)
 local posted=self.postingRow;self.postingRow=nil
 if not posted then return end
 self:RecordPostHistory(posted)
 if self.view~='selling' then return end
 local tiles=self.SellTiles and self:SellTiles(self.sellingRows or {}) or (self.sellingRows or {})
 for i,t in ipairs(tiles) do
  local r=t.row or t
  if r.bag==posted.bag and r.slot==posted.slot then self.selectAfterRefresh=i;break end
 end
 self.selectAfterRefresh=self.selectAfterRefresh or 1
 self.selectedRow=nil;self.postQuote=nil
 self:SetPostPrice(nil)
 self.bagsDirty=true -- refreshed on the next tick while Selling is shown
end)
for _,event in ipairs({'AUCTION_HOUSE_SHOW_ERROR','AUCTION_HOUSE_CLOSED'}) do
 M:RegisterHandler(event,function(self,ev)
  self.postingRow=nil;self.selectAfterRefresh=nil;self.sellCheckAt=nil
  -- A price check cut off by closing the AH must not stay "Checking...".
  if ev=='AUCTION_HOUSE_CLOSED' and self.postQuote and not self.postQuote.at then self.postQuote=nil;self:RefreshUI() end
 end)
end

-- Cancelling ------------------------------------------------------------------
local bands={'Short','Medium','Long','Very long'}
function M:FormatTimeLeft(v)
 v=tonumber(v)
 if not v then return '?' end
 if v>=60 then
  local h=math.floor(v/3600);local m=math.floor(v%3600/60)
  return h>0 and (h..'h '..m..'m') or (m..'m')
 end
 return bands[v+1] or '?'
end
function M:OwnedSold(row)
 return Enum and Enum.AuctionStatus and row.status==Enum.AuctionStatus.Sold or row.status==1
end
function M:OwnedState(o)
 if self:OwnedSold(o) then return '|cff72e7aaSOLD|r' end
 if o.undercut then return '|cffff6655UNDERCUT|r' end
 if o.liveAt then return o.competition and '|cff72e7aaLOWEST|r' or 'NO COMPETITION' end
 if o.action=='CHECKING' then return 'CHECKING' end
 return 'Not checked'
end
-- Your auctions reload often (after posting, opening the AH, Refresh). Keep each
-- auction's undercut check across reloads instead of going back to "Not checked".
local VERDICT={'liveAt','competition','undercut','action','reason','cancelCost','proposedUnit','repriceDifference'}
function M:CopyOwnedVerdict(to,from)
 if to==from or not (to and from) then return end
 for _,k in ipairs(VERDICT) do to[k]=from[k] end
end
-- A live check that finishes after a reload also marks the reloaded row.
function M:SyncOwnedVerdict(row)
 if not (row and row.auctionID) then return end
 for _,o in ipairs(self.ownedRows or {}) do
  if o~=row and o.auctionID==row.auctionID and o.unit==row.unit then self:CopyOwnedVerdict(o,row) end
 end
end
function M:CarryOwnedVerdicts(old,new)
 local by={}
 for _,o in ipairs(old or {}) do if o.auctionID then by[o.auctionID]=o end end
 for _,r in ipairs(new or {}) do
  local o=r.auctionID and by[r.auctionID]
  if o and o.unit==r.unit and (o.liveAt and time()-o.liveAt<900 or o.action=='CHECKING') then self:CopyOwnedVerdict(r,o) end
  if o and self.selectedRow==o then self.selectedRow=r end
  if o and self.shopBuy and self.shopBuy.fromListings==o then self.shopBuy.fromListings=r end
 end
end
function M:ApplyOwnedCompetition(row,competitor)
 row.liveAt=time();row.competition=competitor
 row.undercut=competitor~=nil and row.unit~=nil and competitor<row.unit or false
end
function M:CheckAllUndercuts()
 if not self.ahOpen or not self:CanUseAuctionHouse() then self:Print('Open the Auction House first');return false end
 local groups,order={},{}
 for _,row in ipairs(self.ownedRows or {}) do
  if row.marketKey~=nil and row.itemKey and not self:OwnedSold(row) then
   if not groups[row.marketKey] then groups[row.marketKey]={};order[#order+1]=row.marketKey end
   table.insert(groups[row.marketKey],row);row.action='CHECKING'
  end
 end
 if #order==0 then self:Print('No active listings to check. Click REFRESH MY AUCTIONS.');return false end
 local run={total=0,done=0};self.undercutRun=run
 for _,key in ipairs(order) do
  local rows=groups[key]
  local market=self.db.market[key] or rows[1].itemKey
  local queued=self:Search(market,25,function(result)
   if self.undercutRun~=run then return end
   local competitor=result.rows[1] and result.rows[1].unit
   for _,row in ipairs(rows) do self:ApplyOwnedCompetition(row,competitor);row.action='INSPECT';self:SyncOwnedVerdict(row) end
   run.done=run.done+1;self:RefreshUI()
  end,function(e)
   for _,row in ipairs(rows) do row.action='HOLD';row.reason='Live check failed: '..tostring(e);self:SyncOwnedVerdict(row) end
   if run.live then run.done=run.done+1 end;self:RefreshUI()
  end,function() return self.undercutRun==run end)
  if queued then run.total=run.total+1 else for _,row in ipairs(rows) do if row.action=='CHECKING' then row.action='INSPECT' end end end
 end
 run.live=true
 self:RefreshUI();return run.total>0
end
-- Gold on its way: sold auctions are paid by mail (~1 hour after the sale).
-- Values are after the AH cut. Also what the still-listed auctions are worth
-- if every one sells at its current price.
function M:InboundGold()
 local keep=1-(self.db and self.db.settings.ahCut or 0.05)
 local sold,soldN,listed,listedN,nextIn=0,0,0,0,nil
 for _,o in ipairs(self.ownedRows or {}) do
  local v=(tonumber(o.unit) or 0)*(tonumber(o.quantity) or 0)
  if v>0 and v<1e13 then
   if self:OwnedSold(o) then
    sold=sold+v;soldN=soldN+1
    local t=tonumber(o.timeLeft);if t and t>=60 and (not nextIn or t<nextIn) then nextIn=t end
   else listed=listed+v;listedN=listedN+1 end
  end
 end
 return math.floor(sold*keep),soldN,math.floor(listed*keep),listedN,nextIn
end
function M:UndercutSummary()
 local u,l,n=0,0,0
 for _,o in ipairs(self.ownedRows or {}) do
  if not self:OwnedSold(o) then
   if o.undercut then u=u+1 elseif o.liveAt then l=l+1 else n=n+1 end
  end
 end
 return u,l,n
end
function M:CancelNextUndercut()
 for _,row in ipairs(self.ownedRows or {}) do
  if row.undercut and not self:OwnedSold(row) then
   self.selectedRow=row;self:ReviewCancel(row);self:RefreshUI();return true
  end
 end
 self:Print('No undercut listings found. Click CHECK UNDERCUTS first.');return false
end
M:RegisterHandler('AUCTION_CANCELED',function(self,_,id)
 local rows=self.ownedRows or {}
 for i=#rows,1,-1 do
  if rows[i].auctionID==id then
   if self.selectedRow==rows[i] then self.selectedRow=nil end
   table.remove(rows,i)
  end
 end
 self:RefreshUI()
end)

-- Item names for prices received from the partner account -------------------
-- The receiving account may never have seen an item, so the client has no name
-- for it and a name search would miss it. Names are requested slowly in the
-- background and remembered; a pending name search refreshes when they arrive.
function M:ItemName(id)
 id=tonumber(id);if not id then return end
 local info=C_Item and C_Item.GetItemNameByID or GetItemInfo
 local ok,n=false,nil;if info then ok,n=pcall(info,id) end
 if ok and type(n)=='string' and n~='' then
  if self.db.itemNames[id]~=n and not self.persistenceBlocked then self.db.itemNames[id]=n end
  return n
 end
 local cached=self.db.itemNames[id];return type(cached)=='string' and cached or nil
end
function M:WarmItemNames()
 if not self.db then return end
 -- Snapshot ids (sync may add prices while names load). A running warm-up
 -- picks up ids received since it started.
 local w=self.nameWarm or {ids={},i=0,nextAt=0,requested=0}
 local set=self.nameWarm and self.sharedIdSet or {}
 for _,s in pairs(self.db.sharedPrices) do
  local id=type(s)=='table' and tonumber(s.id)
  if id and not set[id] then set[id]=true;w.ids[#w.ids+1]=id end
 end
 self.sharedIdSet=set;self.nameWarm=w
end
function M:ItemNameTick()
 local w=self.nameWarm
 local shown=self.window and self.window:IsShown()
 -- Loading item data makes the game (and other addons) do work per item, so
 -- names load only while Shopping is open and out of combat: 5 every 0.5s,
 -- each item asked for at most once per session.
 local allowed=shown and self.view=='browse' and not (InCombatLockdown and InCombatLockdown())
 if w and allowed and GetTime()>=w.nextAt then
  w.nextAt=GetTime()+0.5
  local load=C_Item and C_Item.RequestLoadItemDataByID
  self.nameAsked=self.nameAsked or {}
  local sent=0
  while sent<5 do
   w.i=w.i+1;local id=w.ids[w.i]
   if not id then self.nameWarm=nil;break end
   if not self.nameAsked[id] and not self:ItemName(id) and load then
    self.nameAsked[id]=true;pcall(load,id);w.requested=w.requested+1;sent=sent+1
   end
  end
 end
 if self.browseNamesDirty and GetTime()>=self.browseNamesDirty and shown then
  self.browseNamesDirty=nil
  if self.view=='browse' and not self.shoppingListMode and (self.db.settings.filter or '')~='' and not self.queue.dedupe['browse-name'] then
   self:BuildBrowseRows(self.db.settings.filter)
  end
 end
end
M:RegisterHandler('GET_ITEM_INFO_RECEIVED',function(self,_,id,success)
 id=tonumber(id)
 if not id or success==false or not self.db or self.db.itemNames[id] or not (self.sharedIdSet and self.sharedIdSet[id]) then return end
 if self:ItemName(id) then self.browseNamesDirty=self.browseNamesDirty or GetTime()+1 end
end)
