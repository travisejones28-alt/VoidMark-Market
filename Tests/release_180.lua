return function(M,check,jobs,advance,emit)
-- 1.8 Auctionator-style shopping, selling, cancelling and live prices.
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
 M.ahOpen=true;M:CancelRequests('test');M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil;M.queue.nextSend=0
 M.execution={state='idle',message='idle'};M.listSearch=nil;M.listEmpty=nil;M.undercutRun=nil
end
-- Commodity search double: rowsByID[itemID] answers the next search for that item.
local function withSearch(rowsByID,fn)
 local old=C_AuctionHouse;local api=setmetatable({},{__index=old});C_AuctionHouse=api
 local current
 api.IsThrottledMessageSystemReady=function() return true end
 api.GetItemKeyInfo=function() return {isCommodity=true} end
 api.HasSearchResults=function() return false end
 api.SendSearchQuery=function(key) current=key.itemID end
 api.HasFullCommoditySearchResults=function() return true end
 api.GetNumCommoditySearchResults=function(id) return #(rowsByID[id] or {}) end
 api.GetCommoditySearchResultInfo=function(id,i) return rowsByID[id][i] end
 local function serve(n)
  for _=1,n or 30 do
   advance(1);M:PumpQueue()
   if current then local id=current;current=nil;emit('COMMODITY_SEARCH_RESULTS_UPDATED',id);jobs() end
  end
 end
 local ok,err=pcall(fn,api,serve)
 C_AuctionHouse=old;if not ok then error(err,0) end
end
local function tip()
 local lines={}
 return lines,{AddLine=function(_,s)lines[#lines+1]=s end,AddDoubleLine=function(_,a,b)lines[#lines+1]=a..':'..b end}
end

check('1.8 complete live searches record the competitor floor for tooltips without touching scan history',function()
 reset();local oldItem=C_Item;C_Item=nil
 M.db.market[9301]={itemID=9301,marketKey=9301,name='Herb',lastSeen=time()-3600,observations=8,confidenceScore=80,
  fairValue=300,historySpan=10*86400,latest={floor=290},history={{at=1,median=290}}}
 withSearch({[9301]={{unitPrice=250,quantity=7,numOwnerItems=0},{unitPrice=260,quantity=3,numOwnerItems=0}}},function(_,serve)
  local got;M:Search(M.db.market[9301],50,function(r) got=r end);serve()
  assert(got and got.rows[1].unit==250)
 end)
 local e=M.db.liveSeen[9301];assert(e and e.floor==250 and e.quantity==10 and time()-e.at<60)
 assert(#M.db.market[9301].history==1 and M.db.market[9301].latest.floor==290)
 local p=M:PriceObservation(9301);assert(p.floor==250 and p.source=='Live search' and p.fair==M:StoredPriceObservation(9301).fair)
 local lines,t=tip();M:AppendMarketTooltip(t,'|Hitem:9301:0:0:0:0:0:0:0|h[Herb]|h');local text=table.concat(lines,'\n')
 assert(text:find('Auction:'..M:Coins(250),1,true) and not text:find('old)',1,true))
 -- A newer full scan wins again.
 advance(10);M.db.market[9301].lastSeen=time();assert(M:PriceObservation(9301).source=='Local scan')
 C_Item=oldItem
end)

check('1.8 live name search shows available quantity and records each result',function()
 reset();M.view='browse';M.db.settings.filter='Linen'
 local orig=C_AuctionHouse.GetBrowseResults
 C_AuctionHouse.GetBrowseResults=function() return {{itemKey={itemID=61,itemSuffix=0,itemLevel=0},minPrice=43,totalQuantity=120}} end
 M:LiveNameSearch('Linen');M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');jobs()
 C_AuctionHouse.GetBrowseResults=orig
 assert(M.browseRows[1].quantity==120 and M.db.liveSeen[61].floor==43 and M.db.liveSeen[61].quantity==120)
end)

check('1.8 searching a shopping list fetches every item and marks found and not-listed rows',function()
 reset();M:SetList('Mats')
 assert(M:SetWatch(9401,nil) and M:SetWatch(9402,nil))
 withSearch({[9401]={{unitPrice=55,quantity=4,numOwnerItems=0}},[9402]={}},function(_,serve)
  assert(M:SearchShoppingList());assert(M:ListSearchStatus():find('0 / 2',1,true))
  serve()
 end)
 assert(M.listSearch.finished and M.listSearch.found==1 and M.listSearch.none==1 and not M:ListSearchStatus())
 M.shoppingListMode=true;M.db.settings.filter=''
 local byKey={};for _,r in ipairs(M:ShoppingResultRows()) do byKey[r.marketKey]=r end
 assert(byKey[9401].status=='LIVE' and byKey[9401].floor==55 and byKey[9401].quantity==4)
 assert(byKey[9402].status=='NONE' and byKey[9402].floor==0)
 -- AH closed: nothing is queued.
 M.ahOpen=false;assert(not M:SearchShoppingList());M.ahOpen=true
end)

check('1.8 sell price is lowest minus undercut, never below the saved minimum',function()
 reset();local row={marketKey=9501,price=900}
 assert(M:SuggestPostUnit(row,1000)==999)
 M.db.settings.sellUndercut=0;assert(M:SuggestPostUnit(row,1000)==1000)
 M.db.settings.sellUndercut=50;assert(M:SuggestPostUnit(row,1000)==950)
 assert(M:SuggestPostUnit(row,nil)==900) -- no competition: planner suggestion
 assert(M:SuggestPostUnit(row,1)==1) -- never below one copper
 M.db.sellFloors[9501]=980;local unit,held=M:SuggestPostUnit(row,1000);assert(unit==980 and held)
 assert(M:SuggestPostUnit({},nil)==nil)
 assert(M:PostDuration()==3);M.db.settings.postDuration=1;assert(M:PostDuration()==1)
 M.db.settings.postDuration=7;assert(M:PostDuration()==3)
end)

check('1.8 selecting a bag item checks the live price, fills the undercut and posts all commodity units',function()
 reset();M:InitializeUI();M.view='selling'
 local loc,con=ItemLocation,C_Container
 local bag={itemID=9601,hyperlink='herb',stackCount=20}
 ItemLocation={CreateFromBagAndSlot=function() return {} end};C_Container={GetContainerItemInfo=function() return bag end}
 withSearch({[9601]={{unitPrice=1200,quantity=40,numOwnerItems=0}}},function(api,serve)
  api.GetItemKeyFromItem=function() return {itemID=9601,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0} end
  api.GetAvailablePostCount=function() return 55 end
  local row={bag=0,slot=1,itemID=9601,itemLink='herb',name='Herb',quantity=20,marketKey=9601}
  M:SelectSellRow(row,true);assert(M.postQuote and M.postQty:GetText()=='20')
  serve()
  assert(M.postQuote.floor==1200 and M:GetPostPrice()==1199 and M.postSilver:GetText()=='11' and M.postCopper:GetText()=='99' and M.postQty:GetText()=='55')
  -- 1.9.5: an old saved stack size (no longer editable) no longer caps the post.
  M.db.sellStacks[9601]=10;M.selectedRow=nil;M:SelectSellRow(row,true);serve()
  assert(M.postQty:GetText()=='55')
 end)
 ItemLocation=loc;C_Container=con
end)

check('1.8 after a post the next bag item is selected and checked',function()
 reset();M:InitializeUI();M.view='selling'
 local a={bag=0,slot=1,name='A',marketKey=1};local b={bag=0,slot=2,name='B',marketKey=2}
 M.sellingRows={a,b};M.postingRow=a
 local checked;local old=M.CheckPost;M.CheckPost=function(_,r) checked=r end
 local refresh=M.RefreshInventory;M.RefreshInventory=function(self) self:AfterPostRefresh({b}) end
 M.ahOpen=true;M.window:Show()
 emit('AUCTION_HOUSE_AUCTION_CREATED',5)
 assert(M.bagsDirty and not checked) -- 1.9.5: waits for the bags to settle
 M.eventFrame.scripts.OnUpdate(M.eventFrame,0.2)
 assert(M.selectedRow==b and not checked) -- selected now, price checked a moment later
 advance(1);M.eventFrame.scripts.OnUpdate(M.eventFrame,0.2)
 M.CheckPost=old;M.RefreshInventory=refresh
 assert(M.selectedRow==b and checked==b and not M.postingRow)
 -- No post in flight: creation events never move the selection.
 M.selectedRow=a;emit('AUCTION_HOUSE_AUCTION_CREATED',6);assert(M.selectedRow==a)
end)

check('1.8 cancelling checks every listing for undercuts and cancels one per confirmed click',function()
 reset();M:InitializeUI();M.view='my auctions'
 local k1={itemID=9701,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0};local k2={itemID=9702,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0}
 M.ownedRows={
  {auctionID=1,itemKey=k1,marketKey=9701,name='A',quantity=1,unit=500},
  {auctionID=2,itemKey=k1,marketKey=9701,name='A',quantity=1,unit=400},
  {auctionID=3,itemKey=k2,marketKey=9702,name='B',quantity=1,unit=100},
  {auctionID=4,itemKey=k2,marketKey=9702,name='B',quantity=1,unit=100,status=1}}
 local searches=0
 withSearch({[9701]={{unitPrice=450,quantity=2,numOwnerItems=0}},[9702]={}},function(api,serve)
  local send=api.SendSearchQuery;api.SendSearchQuery=function(...) searches=searches+1;return send(...) end
  assert(M:CheckAllUndercuts());serve()
  assert(searches==2) -- one search per item, not per auction; sold rows skipped
  local r=M.ownedRows
  assert(r[1].undercut and not r[2].undercut and r[2].competition==450 and r[3].liveAt and not r[3].competition)
  assert(M:OwnedState(r[1]):find('UNDERCUT',1,true) and M:OwnedState(r[2]):find('LOWEST',1,true))
  assert(M:OwnedState(r[3])=='NO COMPETITION' and M:OwnedState(r[4]):find('SOLD',1,true))
  local u,l,n=M:UndercutSummary();assert(u==1 and l==2 and n==0)
  local asked;local ask=M.AskTrade;M.AskTrade=function(_,msg,cb) asked=msg end
  api.GetOwnedAuctions=function() return {{auctionID=1,itemKey=k1}} end
  api.CanCancelAuction=function() return true end;api.GetCancelCost=function() return 0 end;api.CancelAuction=function() end
  assert(M:CancelNextUndercut() and M.selectedRow==r[1] and asked and asked:find('#1',1,true))
  M.AskTrade=ask
 end)
 emit('AUCTION_CANCELED',1)
 assert(#M.ownedRows==3 and M.selectedRow==nil and not M:CancelNextUndercut())
 M:RenderUI()
end)

check('1.8 time left reads as hours/minutes or a duration band',function()
 assert(M:FormatTimeLeft(7260)=='2h 1m' and M:FormatTimeLeft(600)=='10m')
 assert(M:FormatTimeLeft(0)=='Short' and M:FormatTimeLeft(3)=='Very long' and M:FormatTimeLeft(nil)=='?')
end)

check('1.8 live price cache drops old entries and stays bounded',function()
 reset();local t=M:LiveSeenBook()
 t[1]={floor=5,at=time()-8*86400};t[2]={floor=5,at=time()};t[3]={floor=0,at=time()};t[4]='bad'
 M:PruneLiveSeen();assert(not t[1] and t[2] and not t[3] and not t[4])
 for i=1,5100 do M:RecordLiveFloor(100000+i,10,1) end
 local n=0;for _ in pairs(t) do n=n+1 end;assert(n<=5000)
 M.persistenceBlocked=true;M:RecordLiveFloor(42,10);assert(not t[42]);M.persistenceBlocked=nil
end)
end
