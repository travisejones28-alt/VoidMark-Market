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
 M:PostClicked();assert(sent[1]==row and sent[2]==7 and sent[3]==99 and sent[4]==2 and M.db.settings.postDuration==2)
 sent=nil;M:SetPostPrice(nil);M:PostClicked();assert(not sent)
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
 local r=M.shopScreen.rows[1];assert(r:IsShown() and r.c[2]:GetText()=='Linen' and r.c[3]:GetText()=='120' and r.c[4]:GetText():find('Live',1,true))
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
end
