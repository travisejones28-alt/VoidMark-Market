return function(M,check,jobs,advance,emit)
-- 1.9 Auctionator-style Selling and Shopping screens.
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
 M.ahOpen=true;M:CancelRequests('test');M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil;M.queue.nextSend=0
 M.execution={state='idle',message='idle'};M.listSearch=nil;M.listEmpty=nil;M.selectedRow=nil;M.postQuote=nil;M.tradePending=nil
 M:InitializeUI()
end
local function bagRow(slot,key,name,qty) return {bag=0,slot=slot,itemID=key,marketKey=key,name=name,quantity=qty or 1,itemLink='l'..slot} end

check('1.9 bag tiles merge stacks per item, put favourites first and group by item type',function()
 reset()
 local oldItem=C_Item;C_Item={GetItemInfoInstant=function(id) if id==2 then return id,'Weapon','x','',0,2 end return id,'Trade Goods','x','',0,7 end}
 local rows={bagRow(1,1,'Cloth',20),bagRow(2,1,'Cloth',5),bagRow(3,2,'Sword'),bagRow(4,3,'Herb',4)}
 local t=M:SellTiles(rows)
 assert(#t==3 and t[1].row.name=='Sword' and t[1].class=='Weapon' and t[2].count==25 and t[2].row==rows[1])
 M:ToggleSellFavourite(3);t=M:SellTiles(rows);assert(t[1].row.name=='Herb' and t[1].fav)
 M:ToggleSellFavourite(3);assert(not M.db.sellFavourites[3])
 M.sellingRows=rows;M:SetView('selling');M.sellingRows=rows;M:RenderUI()
 local s=M.sellScreen;assert(s:IsShown() and s.tiles[1]:IsShown() and not s.tiles[4])
 assert(s.headers[1]:GetText()=='Weapon' and s.headers[2]:GetText()=='Trade Goods')
 assert(s.name:GetText()=='Select an item')
 C_Item=oldItem
end)

check('1.9 price boxes round-trip copper and Post sends exact copper, quantity and duration',function()
 reset();M.view='selling'
 M:SetPostPrice(123456);assert(M.postGold:GetText()=='12' and M.postSilver:GetText()=='34' and M.postCopper:GetText()=='56')
 assert(M:GetPostPrice()==123456)
 M.postSilver:SetText('100');assert(M:GetPostPrice()==nil)
 M.postSilver:SetText('');assert(M:GetPostPrice()==120056)
 M:SetPostPrice(nil);assert(M:PostPriceEmpty())
 local sent;local old=M.ReviewPost;M.ReviewPost=function(_,row,n,unit,d) sent={row,n,unit,d} end
 local row=bagRow(1,5,'Ore',10);M.selectedRow=row;M.postQty:SetText('7');M:SetPostPrice(99);M:SetDuration(2)
 M.postQuote={row=row,at=GetTime()}
 M:PostClicked();assert(sent[1]==row and sent[2]==7 and sent[3]==99 and sent[4]==2 and M.db.settings.postDuration==2)
 sent=nil;M:SetPostPrice(nil);M:PostClicked();assert(not sent)
 -- A quote older than a minute is refreshed instead of posting; the typed price stays.
 local rechecked;local oldCheck=M.CheckPost;M.CheckPost=function(_,r) rechecked=r end
 M:SetPostPrice(99);advance(61);M:PostClicked()
 assert(not sent and rechecked==row and M:GetPostPrice()==99 and M.postQuote==nil)
 M.CheckPost=oldCheck
 M.ReviewPost=old
end)

check('1.9 listings show every price with your own marked; clicking one sets the price',function()
 reset();M.view='selling';local row=bagRow(1,5,'Ore',10);M.selectedRow=row
 M.postQuote={row=row,at=GetTime(),floor=100,listings={{unit=90,quantity=2,own=true},{unit=100,quantity=3,own=false},{unit=100,quantity=4,own=false},{unit=120,quantity=1,own=false}}}
 local list=M:SellListRows();assert(#list==3 and list[1].own and list[2].quantity==7)
 M:PickListing(list[2]);assert(M:GetPostPrice()==99)
 M:PickListing(list[1]);assert(M:GetPostPrice()==90) -- your own price is matched, not undercut
 M.sellMode='mine';M.db.postHistory[5]={{at=time(),unit=77,quantity=3,duration=3}};assert(M:SellListRows()[1].unit==77)
 M.sellMode='history';M.db.market[5]={itemID=5,marketKey=5,history={{at=1,median=50,quantity=9},{at=2,median=60,quantity=8}}}
 list=M:SellListRows();assert(list[1].unit==60 and list[2].unit==50)
 M.sellMode='current';M.sellingRows={row};M:SetView('selling');M.selectedRow=row;M.postQuote.at=GetTime();M:RenderUI()
 assert(M.sellScreen.rows[1]:IsShown() and M.sellScreen.rows[1].c[4]:GetText():find('Yes',1,true))
end)

check('1.9 live searches keep every listing, including your own',function()
 reset();local old=C_AuctionHouse;local api=setmetatable({},{__index=old});C_AuctionHouse=api
 local cur
 api.IsThrottledMessageSystemReady=function() return true end;api.GetItemKeyInfo=function() return {isCommodity=true} end
 api.HasSearchResults=function() return false end;api.SendSearchQuery=function(k) cur=k.itemID end
 api.HasFullCommoditySearchResults=function() return true end
 local rows={{unitPrice=80,quantity=5,numOwnerItems=5},{unitPrice=90,quantity=6,numOwnerItems=2}}
 api.GetNumCommoditySearchResults=function() return #rows end;api.GetCommoditySearchResultInfo=function(_,i) return rows[i] end
 local got;M:Search({itemID=8801},50,function(r) got=r end)
 for _=1,5 do advance(1);M:PumpQueue();if cur then local id=cur;cur=nil;emit('COMMODITY_SEARCH_RESULTS_UPDATED',id);jobs() end end
 C_AuctionHouse=old
 assert(got and #got.rows==1 and got.rows[1].unit==90 and got.rows[1].quantity==4) -- competitors only
 assert(#got.all==2 and got.all[1].own and got.all[1].quantity==5 and got.all[2].own)
end)

check('1.9 Skip moves to the next item and a post is recorded in Your history',function()
 reset();M.view='selling'
 local a,b=bagRow(1,1,'A'),bagRow(2,2,'B');M.sellingRows={a,b}
 local oldCheck=M.CheckPost;M.CheckPost=function() end
 M:SelectSellRow(a,true);M:SkipSellItem();assert(M.selectedRow==b);M:SkipSellItem();assert(M.selectedRow==a)
 a.postedUnit=150;a.postedQuantity=2;a.postedDuration=3;M.postingRow=a
 local refresh=M.RefreshInventory;M.RefreshInventory=function(self) self:AfterPostRefresh({a,b}) end
 emit('AUCTION_HOUSE_AUCTION_CREATED',9)
 M.RefreshInventory=refresh;M.CheckPost=oldCheck
 local h=M.db.postHistory[1];assert(h and h[1].unit==150 and h[1].quantity==2 and h[1].duration==3)
end)

check('1.9 shopping screen searches by name, keeps recent searches and opens lists',function()
 reset();M:SetView('browse')
 local live;local old=M.LiveNameSearch;M.LiveNameSearch=function(_,t) live=t end
 M:ShopSearch('  Linen ');assert(live=='Linen' and M.db.settings.filter=='Linen' and M.db.recentSearches[1]=='Linen')
 M:ShopSearch('Wool');M:ShopSearch('linen');assert(#M.db.recentSearches==2 and M.db.recentSearches[1]=='linen')
 M:ShopSearch('a');assert(live=='linen') -- too short
 M.ahOpen=false;live=nil;M:ShopSearch('Silk');assert(not live and M.shoppingSearchStatus:find('Open the Auction House',1,true));M.ahOpen=true
 M.LiveNameSearch=old
 M.shopLeft='recent';M:RenderUI();assert(M.shopScreen.leftRows[1].value=='Silk')
 local searched=0;local oldList=M.SearchShoppingList;M.SearchShoppingList=function() searched=searched+1 end
 M:OpenShoppingList('Mats');assert(M.shoppingListMode and M.activeList=='Mats' and searched==1)
 M.SearchShoppingList=oldList
 M.shopLeft='lists';M:RenderUI();local names={}
 for _,r in ipairs(M.shopScreen.leftRows) do if r.value then names[#names+1]=r.value end end
 assert(names[1]=='Shopping' and names[2]=='Mats')
 M.browseRows={{marketKey=61,itemID=61,name='Linen',floor=43,quantity=120,status='LIVE BROWSE'}};M.shoppingListMode=false;M:RenderUI()
 local r=M.shopScreen.rows[1];assert(r:IsShown() and r.c[2]:GetText()=='Linen' and r.c[3]:GetText()=='120')
 r.scripts.OnClick(r);assert(M.selectedRow.marketKey==61)
 M:ShopAddSelected();assert(M:ListBook(M.activeList)[61])
end)

check('1.9 synced prices become searchable by name once the client learns the item name',function()
 reset();M:SetView('browse');M.ahOpen=false
 local known={};local requested={}
 local oldItem,oldInfo=C_Item,GetItemInfo
 C_Item={GetItemNameByID=function(id) return known[id] end,RequestLoadItemDataByID=function(id) requested[#requested+1]=id end}
 M.db.sharedPrices[2589]={id=2589,key=2589,floor=40,at=time()}
 M:ShopSearch('linen cloth');jobs();M:RenderUI()
 assert(#M.browseRows==0 and M.shoppingSearchStatus:find('Open the Auction House',1,true))
 M.shoppingSearchStatus=nil;M:RenderUI();assert(M.shopScreen.empty:GetText():find('No saved prices match',1,true))
 advance(1);M:ItemNameTick();assert(requested[1]==2589)
 known[2589]='Linen Cloth';emit('GET_ITEM_INFO_RECEIVED',2589,true);assert(M.db.itemNames[2589]=='Linen Cloth')
 advance(2);M:ItemNameTick();jobs()
 assert(M.browseRows[1] and M.browseRows[1].name=='Linen Cloth' and M.browseRows[1].floor==40)
 known[2589]=nil;assert(M:ItemName(2589)=='Linen Cloth') -- remembered after the client forgets it
 C_Item,GetItemInfo=oldItem,oldInfo
end)

check('1.9 Cancelling screen lists undercut auctions first and enables the right buttons',function()
 reset();M:SetView('my auctions');M.ahOpen=true
 local k={itemID=1}
 M.ownedRows={{auctionID=1,itemKey=k,name='B',quantity=1,unit=50,liveAt=1,competition=60},
  {auctionID=2,itemKey=k,name='A',quantity=1,unit=50,liveAt=1,competition=40,undercut=true},
  {auctionID=3,itemKey=k,name='C',quantity=1,unit=50},{auctionID=4,itemKey=k,name='D',quantity=1,unit=50,status=1}}
 local order={};for _,o in ipairs(M:CancelRows()) do order[#order+1]=o.auctionID end
 assert(table.concat(order,',')=='2,3,1,4')
 M:RenderUI();local s=M.cancelScreen
 assert(s:IsShown() and s.rows[1].c[1]:GetText()=='A' and s.rows[1].c[6]:GetText():find('UNDERCUT',1,true))
 assert(s.next.enabled and not s.cancel.enabled and s.summary:GetText():find('1 undercut',1,true))
 local analyzed;local old=M.AnalyzeOwnedLive;M.AnalyzeOwnedLive=function(_,r) analyzed=r end
 s.rows[2].scripts.OnClick(s.rows[2]);M.AnalyzeOwnedLive=old
 assert(M.selectedRow.auctionID==3 and analyzed==M.selectedRow);M:RenderUI();assert(s.cancel.enabled)
 M.ownedRows={};M.ahOpen=false;M:RenderUI();assert(s.empty:GetText():find('Open the Auction House',1,true) and not s.refresh.enabled)
end)

check('1.9 the shopping list column scrolls when there are more lists than fit',function()
 reset();M:SetView('browse');M.shopExpanded=nil
 for i=1,23 do M:SetList(('List%02d'):format(i)) end
 M.shopLeft='lists';M.shopLeftOffset=0;M:RenderUI();assert(M.shopScreen.leftRows[1].value=='Shopping')
 M.shopScreen.left.scripts.OnMouseWheel(M.shopScreen.left,-1);M:RenderUI()
 assert(M.shopLeftOffset==3 and M.shopScreen.leftRows[1].value=='List03')
 M.shopLeftOffset=99;M:RenderUI();assert(M.shopLeftOffset==4 and M.shopScreen.leftRows[20].value=='List23')
end)

check('1.9.1 a minimum can be saved for an item this account never scanned; owned rows carry ids and names',function()
 reset()
 assert(M.db.market[7777]==nil and M:SetSellFloor(7777,12345) and M.db.sellFloors[7777]==12345)
 assert(M:SetSellFloor(7777,nil) and M.db.sellFloors[7777]==nil)
 assert(not M:SetSellFloor('bad key',5))
 local old=C_AuctionHouse;local api=setmetatable({},{__index=old});C_AuctionHouse=api
 local oldItem=C_Item;C_Item={GetItemNameByID=function(id) return id==7777 and 'Silk Cloth' or nil end}
 api.GetOwnedAuctions=function() return {{auctionID=5,itemKey={itemID=7777,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0},quantity=2,unitPrice=10,status=0}} end
 M:CaptureOwnedAuctions();jobs()
 C_AuctionHouse=old;C_Item=oldItem
 local r=M.ownedRows[1];assert(r and r.itemID==7777 and r.name=='Silk Cloth' and r.status==0)
end)

check('1.9.1 sync keeps several pages in flight, rate-limits bytes and resends after a lost page',function()
 local old=C_ChatInfo;local sent={}
 C_ChatInfo={RegisterAddonMessagePrefix=function()return 0 end,SendAddonMessage=function(_,msg,ch,target) sent[#sent+1]=msg;return 0 end}
 local ok,err=pcall(function()
  reset();M:PairPeer('Bank');jobs()
  local j=M.db.shareJournal;local r=M.shareRun
  j.seq=0;j.rows={};j.latest={}
  for i=1,300 do j.seq=i;j.rows[i]='P,'..(50000+i)..','..time()..','..(100+i)..',0,0' end
  M.shareRegistered=true;r.lastContact=GetTime();r.hello=GetTime()+100;r.cursor=0;r.next=0
  local function page(msg) local f={};for v in (msg..'\t'):gmatch('([^\t]*)\t') do f[#f+1]=v end;return tonumber(f[4]),tonumber(f[5]),f[2] end
  local function ack(n) M:ReceiveSharing('VMMkt2',M.economyID..'\tQ\t'..j.epoch..'\t'..n,'WHISPER','Bank-TestRealm') end
  M:PumpSharing()
  assert(#sent==8) -- several pages at once instead of one per reply
  local prev=0;for _,m in ipairs(sent) do local lo,hi,kind=page(m);assert(kind=='D' and lo==prev and hi>lo);prev=hi end
  local bytes=0;for _,m in ipairs(sent) do bytes=bytes+#m+1 end;assert(bytes<=3000)
  r.next=0;M:PumpSharing();assert(#sent==8) -- window full
  local _,third=page(sent[3]);ack(third);assert(r.cursor==third and #r.pages==5)
  advance(1);r.next=0;M:PumpSharing();assert(#sent>8 and #sent<=11) -- refilled budget only
  local lo=page(sent[9]);assert(lo==prev)
  -- The receiver repeats the same reply when a page went missing: resend from there.
  ack(third);assert(r.sentHi==third and #r.pages==0)
  advance(1);r.next=0;local before=#sent;M:PumpSharing();assert(#sent>before and page(sent[before+1])==third)
  -- No reply at all: after the 4s deadline the unconfirmed pages are sent again.
  local _,top=page(sent[#sent]);advance(5);r.next=0;before=#sent;M:PumpSharing()
  assert(#sent>before and page(sent[before+1])==third and r.sentHi>third)
  -- A throttled send waits briefly and keeps its place.
  C_ChatInfo.SendAddonMessage=function() return 3 end
  advance(5);r.next=0;local hi=r.sentHi;M:PumpSharing();assert(r.throttleUntil and r.throttleUntil>GetTime())
  -- Everything confirmed: done.
  C_ChatInfo.SendAddonMessage=function(_,msg) sent[#sent+1]=msg;return 0 end
  ack(j.seq);assert(r.cursor==j.seq and #r.pages==0);advance(3);r.next=0;before=#sent;M:PumpSharing();assert(#sent==before)
 end)
 C_ChatInfo=old;if not ok then error(err,0) end
end)

check('1.9.3 live-search prices reach the partner without touching its estimate; one-click posting is opt-in',function()
 reset();M:PairPeer('Bank');jobs()
 local j=M.db.shareJournal;j.seq=0;j.rows={};j.latest={}
 M:RecordLiveFloor(4242,77,9)
 local line=j.rows[j.seq];assert(line=='P,4242,'..time()..',77,0,0')
 local seq=j.seq;advance(60);M:RecordLiveFloor(4242,77,9);assert(j.seq==seq) -- unchanged: not repeated yet
 M:RecordLiveFloor(4242,70,9);assert(j.seq==seq+1 and j.rows[j.seq]:find(',70,0,0',1,true))
 advance(1801);M:RecordLiveFloor(4242,70,9);assert(j.seq==seq+2)
 M.db.settings.shareLivePrices=false;advance(5);M:RecordLiveFloor(4242,60,9);assert(j.seq==seq+2);M.db.settings.shareLivePrices=nil
 -- Receiver: the live row updates the price and keeps the history estimate.
 M.db.sharedPrices[4242]={kind='P',key=4242,id=4242,at=time()-3600,floor=90,fair=95,reliable=true,histAt=time()-3600,histFair=95,origin=M.db.syncPeer}
 M:MergeAsk({kind='P',key=4242,id=4242,at=time(),floor=70,fair=nil,reliable=false,confidence=0})
 local p=M.db.sharedPrices[4242];assert(p.floor==70 and p.histFair==95 and p.histAt==time()-3600)
 -- Posting asks by default; the Selling screen box reflects and saves it.
 M:InitializeUI();M.view='selling';M.sellingRows={};M:RenderUI();assert(M.sellScreen.confirm:GetChecked())
 M.sellScreen.confirm:SetChecked(false);M.sellScreen.confirm.scripts.OnClick(M.sellScreen.confirm);assert(M.db.settings.confirmPosts==false)
 M.sellScreen.confirm:SetChecked(true);M.sellScreen.confirm.scripts.OnClick(M.sellScreen.confirm);assert(M.db.settings.confirmPosts==true)
end)

check('1.9.4 no background bag, crafting or item-name work while the window is closed; /vmm perf reports',function()
 reset();M.view='selling';M.window:Hide()
 local inv,craft=0,0;local oldInv,oldCraft=M.RefreshInventory,M.RebuildCrafting
 M.RefreshInventory=function() inv=inv+1 end;M.RebuildCrafting=function() craft=craft+1 end
 M.sellingRows={{itemID=5,name='Item 5'}}
 emit('GET_ITEM_INFO_RECEIVED',5,true);emit('BAG_UPDATE_DELAYED')
 for _=1,5 do advance(0.2);M.eventFrame.scripts.OnUpdate(M.eventFrame,0.2) end
 assert(inv==0 and craft==0 and M.craftingStale)
 -- Opening a crafting screen rebuilds once.
 M:SetView('crafting');assert(craft==1 and not M.craftingStale)
 -- Selling on screen: an unnamed bag item loading refreshes bags; others don't.
 M:SetView('selling');inv=0;M.sellingRows={{itemID=5,name='Item 5'},{itemID=6,name='Ore'}};M.bagsDirty=false
 emit('GET_ITEM_INFO_RECEIVED',6,true);assert(not M.bagsDirty)
 emit('GET_ITEM_INFO_RECEIVED',5,true);assert(M.bagsDirty)
 M.RefreshInventory,M.RebuildCrafting=oldInv,oldCraft
 -- Name lookups wait for the Shopping screen and ask for each item once.
 local asked=0;local oldItem=C_Item;C_Item={GetItemNameByID=function() return nil end,RequestLoadItemDataByID=function() asked=asked+1 end}
 for i=1,12 do M.db.sharedPrices[80000+i]={id=80000+i,key=80000+i,floor=1,at=time()} end
 M.nameWarm=nil;M.nameAsked=nil;M:WarmItemNames();M.window:Hide()
 for _=1,4 do advance(1);M:ItemNameTick() end;assert(asked==0)
 M:SetView('browse')
 advance(1);M:ItemNameTick();assert(asked==5)
 advance(0.2);M:ItemNameTick();assert(asked==5) -- paced
 for _=1,5 do advance(1);M:ItemNameTick() end;assert(asked==12)
 M:WarmItemNames();for _=1,5 do advance(1);M:ItemNameTick() end;assert(asked==12) -- never asked twice
 C_Item=oldItem
 -- /vmm perf collects and reports.
 local printed={};local oldPrint=M.Print;M.Print=function(_,s) printed[#printed+1]=s end
 M:StartPerf(1);emit('BAG_UPDATE_DELAYED');advance(2);M.eventFrame.scripts.OnUpdate(M.eventFrame,0.2)
 M.Print=oldPrint;assert(not M.perf and table.concat(printed,'\n'):find('ms/s',1,true))
end)

check('1.9.5 three stacks post as one 60-unit post, a locked slot is retried, closing the AH ends "Checking"',function()
 reset();M:InitializeUI();M:SetView('selling');M.ahOpen=true
 local rows={{bag=0,slot=1,itemID=2589,itemLink='linen',name='Linen Cloth',quantity=20,marketKey=2589},
  {bag=0,slot=2,itemID=2589,itemLink='linen',name='Linen Cloth',quantity=20,marketKey=2589},
  {bag=0,slot=3,itemID=2589,itemLink='linen',name='Linen Cloth',quantity=20,marketKey=2589}}
 M.sellingRows=rows
 local loc,con=ItemLocation,C_Container;local locked=true
 ItemLocation={CreateFromBagAndSlot=function() return {} end}
 C_Container={GetContainerItemInfo=function(_,slot) return {itemID=2589,hyperlink='linen',stackCount=20,isLocked=locked and slot==1} end}
 local old=C_AuctionHouse;local api=setmetatable({},{__index=old});C_AuctionHouse=api
 local cur;api.IsThrottledMessageSystemReady=function() return true end
 api.GetItemKeyFromItem=function() return {itemID=2589,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0} end
 api.GetItemKeyInfo=function() return {isCommodity=false} end
 api.GetAvailablePostCount=function() return 60 end
 api.HasSearchResults=function() return false end;api.SendSearchQuery=function(k) cur=k end
 api.HasFullItemSearchResults=function() return true end;api.GetNumItemSearchResults=function() return 0 end
 api.CalculateItemDeposit=function(_,_,n) return n end
 local posted;api.PostItem=function(_,d,n,bid,unit) posted={d,n,unit};return false end
 local printed={};local oldPrint=M.Print;M.Print=function(_,s) printed[#printed+1]=s end
 local ok,err=pcall(function()
  M:SelectSellRow(rows[1],true)
  assert(M.postQty:GetText()=='60' and not M.postQuote and M.sellCheckAt and #printed==0) -- locked: retry, no error
  locked=false;advance(1);M.eventFrame.scripts.OnUpdate(M.eventFrame,0.2)
  assert(M.postQuote and not M.postQuote.at)
  for _=1,5 do advance(1);M:PumpQueue();if cur then local k=cur;cur=nil;emit('ITEM_SEARCH_RESULTS_UPDATED',k);jobs() end end
  assert(M.postQuote.at and M.postQty:GetText()=='60')
  M:SetPostPrice(500);M.db.settings.confirmPosts=false;M:PostClicked()
  assert(posted and posted[2]==60 and posted[3]==500)
  -- Closing the AH mid-check leaves no stuck "Checking live price".
  M.tradePending=nil;M.postQuote={row=rows[1]};emit('AUCTION_HOUSE_CLOSED');assert(M.postQuote==nil)
 end)
 M.Print=oldPrint;C_AuctionHouse=old;ItemLocation=loc;C_Container=con;M.db.settings.confirmPosts=nil
 if not ok then error(err,0) end
end)
end
