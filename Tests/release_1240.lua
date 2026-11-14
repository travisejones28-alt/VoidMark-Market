return function(M,check,jobs,advance,emit)
-- 1.23.21 Clear Filters button, chain buy, Shopping buys skip the quantity cap.
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
 M.ahOpen=true;M:CancelRequests('test');M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil;M.queue.nextSend=0
 M.execution={state='idle',message='idle'};M.db.pending={};M.db.quoteGuardUntil=0;M.selectedRow=nil;M.shopBuy=nil
 M:InitializeUI();M:SetView('browse')
end
local function fakeAH(com,rows)
 local old=C_AuctionHouse;local api=setmetatable({},{__index=old});C_AuctionHouse=api;local log={}
 api.IsThrottledMessageSystemReady=function() return true end
 api.GetItemKeyInfo=function() return {isCommodity=com} end
 api.HasSearchResults=function() return false end
 api.SendSearchQuery=function() log[#log+1]='search' end
 api.HasFullCommoditySearchResults=function() return true end;api.HasFullItemSearchResults=function() return true end
 api.GetNumCommoditySearchResults=function() return #rows end;api.GetNumItemSearchResults=function() return #rows end
 api.GetCommoditySearchResultInfo=function(_,i) return rows[i] end;api.GetItemSearchResultInfo=function(_,i) return rows[i] end
 api.StartCommoditiesPurchase=function(id,q) log[#log+1]='quote:'..id..':'..q end
 api.ConfirmCommoditiesPurchase=function(id,q) log[#log+1]='confirm:'..id..':'..q end
 api.CancelCommoditiesPurchase=function() log[#log+1]='cancel' end
 api.PlaceBid=function(id,c) log[#log+1]='bid:'..id..':'..c end
 api.SendBrowseQuery=function() log[#log+1]='browse' end
 return log,function() C_AuctionHouse=old end
end
local popups={}
local function stubPopups()
 local d,s,h=StaticPopupDialogs,StaticPopup_Show,StaticPopup_Hide;popups={}
 StaticPopupDialogs={}
 StaticPopup_Show=function(which,text,_,data) popups[#popups+1]={text=text,data=data} end
 StaticPopup_Hide=function() end
 return function() StaticPopupDialogs,StaticPopup_Show,StaticPopup_Hide=d,s,h end
end
local function answer(com,key) advance(1);M:PumpQueue();emit(com and 'COMMODITY_SEARCH_RESULTS_UPDATED' or 'ITEM_SEARCH_RESULTS_UPDATED',key);jobs() end
local function run(fn,...) local restore={...};local ok,err=pcall(fn);for _,r in ipairs(restore) do r() end;if not ok then error(err,0) end end

check('1.23.21 Clear Filters empties Level, Price and More... and searches again',function()
 reset();local log,restoreAH=fakeAH(true,{})
 run(function()
  M:SetShopLevelRange(40,49);M:SetShopPriceRange('1','5');M.shopFilters={maxPrice=100}
  M.db.settings.filter='peacebloom';M.shoppingListMode=false
  M:RenderUI();local s=M.shopScreen
  assert(M:ShopFiltersActive() and s.clearFilters.enabled,'button lights up when a filter is on')
  local searched,old=nil,M.LiveNameSearch
  M.LiveNameSearch=function(self,text) searched=text end
  s.clearFilters.scripts.OnClick(s.clearFilters)
  M.LiveNameSearch=old
  local lo,hi=M:ShopLevelRange();local plo,phi=M:ShopPriceRange()
  assert(not lo and not hi and not plo and not phi and M.shopFilters==nil,'all filters cleared')
  assert(s.minLevel:GetText()=='' and s.maxPrice:GetText()=='','boxes emptied')
  assert(searched=='peacebloom','searched again without the level')
  M:RenderUI();assert(not s.clearFilters.enabled,'nothing left to clear')
 end,restoreAH)
end)

check('1.23.21 Filter row hides under the buy view (no overlap with Your gold)',function()
 reset();local log,restoreAH=fakeAH(true,{{unitPrice=71,quantity=20,numOwnerItems=0}})
 run(function()
  M:ShopBuyOpen({marketKey=2447,name='Peacebloom'});answer(true,2447);M:RenderUI()
  local s=M.shopScreen
  assert(s.buyView:IsShown() and not s.minPrice:IsShown() and not s.clearFilters:IsShown())
  M:ShopBuyClose();M:RenderUI();assert(s.minPrice:IsShown() and s.clearFilters:IsShown())
 end,restoreAH)
end)

check('1.23.21 Shopping buys are not capped by the quantity limit',function()
 reset();local rows={{unitPrice=71,quantity=500,numOwnerItems=0}}
 local log,restoreAH=fakeAH(true,rows)
 run(function()
  M.db.settings.maxQuantity=20
  M:ShopBuyOpen({marketKey=2447,name='Peacebloom'});answer(true,2447)
  M:ShopBuySetQuantity(200);M:RenderUI()
  local v=M.shopScreen.buyView
  assert(v.buyNow.enabled and not v.status:GetText():find('quantity limit',1,true))
 end,restoreAH)
end)

check('1.23.21 Chain buy (items): next cheapest listing is lined up after each buy, stops above the cap',function()
 reset()
 local key={itemID=4500,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0}
 local rows={{auctionID=11,quantity=1,buyoutAmount=900,itemKey=key},{auctionID=12,quantity=1,buyoutAmount=950,itemKey=key},{auctionID=13,quantity=1,buyoutAmount=900,itemKey=key}}
 local log,restoreAH=fakeAH(false,rows);local restoreP=stubPopups()
 local oldItem=C_Item;C_Item={GetItemMaxStackSizeByID=function() return 20 end}
 run(function()
  M.db.settings.shopChainBuy=true
  M:ShopBuyOpen({marketKey=4500,name='Silk Cloth Bag'});answer(false,key);M:RenderUI()
  local v=M.shopScreen.buyView;assert(v.chain:GetChecked(),'checkbox shows the setting')
  M:ShopBuyNow();popups[1].data.accept();assert(log[#log]:find('^bid:1[13]:900'),'first buy at 900')
  assert(M.shopBuy.chainMax==900)
  table.remove(rows,1)
  emit('AUCTION_HOUSE_PURCHASE_COMPLETED',11);answer(false,key)
  assert(#popups==2 and popups[2].text:find('Paying',1,true),'next buy lined up by itself: '..tostring(M.shopBuy.chainStopped)..' next='..tostring(M.shopBuy.chainNext)..' state='..tostring(M.execution.state)..' search='..tostring(M.shopBuy.searching))
  assert(M.shopBuy.rows[M.shopBuy.pick].unit==900,'cheapest left picked')
  popups[2].data.accept();assert(log[#log]=='bid:13:900')
  table.remove(rows,2)
  emit('AUCTION_HOUSE_PURCHASE_COMPLETED',13);answer(false,key)
  assert(#popups==2,'950 is above the 900 cap - no popup')
  M:RenderUI();assert(v.status:GetText():find('Chain buy stopped',1,true))
 end,restoreAH,restoreP,function() C_Item=oldItem end)
end)

check('1.23.21 Chain buy (commodities): same quantity again after the guard; cancel stops it',function()
 reset();local rows={{unitPrice=71,quantity=50,numOwnerItems=0},{unitPrice=72,quantity=50,numOwnerItems=0}}
 local log,restoreAH=fakeAH(true,rows);local restoreP=stubPopups()
 local timers={};local oldTimer=C_Timer;C_Timer=setmetatable({After=function(d,fn) timers[#timers+1]=fn end},{__index=oldTimer})
 run(function()
  M.db.settings.shopChainBuy=true
  M:ShopBuyOpen({marketKey=2447,name='Peacebloom'});answer(true,2447)
  M:ShopBuySetQuantity(20);M:ShopBuyNow();emit('COMMODITY_PRICE_UPDATED',71,1420)
  popups[1].data.accept();assert(log[#log]=='confirm:2447:20')
  rows[1].quantity=30
  emit('COMMODITY_PURCHASE_SUCCEEDED');answer(true,2447)
  -- Either straight away or after the commodity guard, the next quote is asked.
  if not log[#log]:find('^quote') then for _,fn in ipairs(timers) do fn() end end
  assert(log[#log]=='quote:2447:20','chain asked for the next 20')
  emit('COMMODITY_PRICE_UPDATED',71,1420)
  local p=popups[#popups];p.data.cancel()
  M:RenderUI();assert(M.execution.state=='invalid' and not M.shopBuy.chainNext)
 end,restoreAH,restoreP,function() C_Timer=oldTimer end)
end)
check('1.23.22 Listings/sale alert: stack price read right whether Forever gives it per item or for the stack',function()
 local A=C_AuctionHouse;local saved={A.GetOwnedAuctions,A.GetItemKeyInfo}
 local rose=M:Key(2452,0,0,0);local silk=M:Key(4306,0,0,0)
 M.db.market[rose]={name='Rosecap',latest={floor=1500}};M.db.market[silk]={name='Silk Cloth',latest={floor=190}}
 A.GetOwnedAuctions=function() return {
  {auctionID=1,itemKey={itemID=2452,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0},quantity=3,buyoutAmount=1589,status=0},
  {auctionID=2,itemKey={itemID=4306,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0},quantity=15,buyoutAmount=2880,status=0}} end
 A.GetItemKeyInfo=function(k) return {isCommodity=true,itemName=k.itemID==2452 and 'Rosecap' or 'Silk Cloth'} end
 local ok,err=pcall(function()
  M:CaptureOwnedAuctions();jobs()
  local by={};for _,o in ipairs(M.ownedRows) do by[o.auctionID]=o end
  assert(by[1].unit==1589,'Rosecap each: '..tostring(by[1].unit))
  assert(by[2].unit==192,'Silk each: '..tostring(by[2].unit))
  M.saleClaimed={}
  local a=M:BuildSaleAlert('Silk Cloth',2)
  assert(a.qty==15 and a.gross==2880,'sold 15 Silk for '..tostring(a.gross))
 end)
 A.GetOwnedAuctions,A.GetItemKeyInfo=saved[1],saved[2];M.ownedRows=nil;M.db.keyNames=nil
 M.db.market[rose]=nil;M.db.market[silk]=nil;M.db.ownedSnapshot=nil;assert(ok,err)
end)
check('1.23.23 Selling: a mis-posted cheap listing is marked; double-click opens Buy with it lined up; Back returns',function()
 reset();local rows={{unitPrice=105,quantity=2,numOwnerItems=0},{unitPrice=249,quantity=7,numOwnerItems=0},{unitPrice=250,quantity=45,numOwnerItems=0}}
 local log,restoreAH=fakeAH(true,rows)
 run(function()
  local key=M:Key(12037,0,0,0)
  local sel={marketKey=key,name='Mystery Meat',itemID=12037}
  M:SetView('selling');M.selectedRow=sel
  local list={{unit=105,quantity=2},{unit=249,quantity=7},{unit=250,quantity=45},{unit=251,quantity=41}}
  assert(M:SellRowCheap(list[1],list) and not M:SellRowCheap(list[2],list),'1s 5c among 2s 50c is cheap')
  -- Wool Cloth: 1s 40c next to 1s 42c-1s 50c is normal even with pricey listings further down.
  local wool={{unit=140},{unit=142},{unit=143},{unit=148},{unit=149},{unit=150},{unit=163},{unit=400},{unit=500},{unit=600},{unit=700},{unit=800}}
  for i=1,3 do assert(not M:SellRowCheap(wool[i],wool),'Wool row '..i..' is not cheap') end
  M:SellOpenBuy(list[1]);answer(true,key)
  assert(M.shopBuy and M.shopBuy.fromSelling==sel,'buy view from Selling')
  assert(M.shopBuy.quantity==2,'just the cheap ones: '..tostring(M.shopBuy.quantity))
  M:RenderUI();assert(M.shopScreen.buyView:IsShown(),'buy view shows on the Selling tab')
  M:ShopBuyClose();assert(M.selectedRow==sel);M:RenderUI()
  assert(M.sellScreen:IsShown() and not M.shopScreen:IsShown(),'Back returns to Selling')
 end,restoreAH)
end)
check('1.23.24 Selling: AH answers 0 for "can post" - still post when the AH accepts it; say why once when it doesn\'t',function()
 reset()
 local loc,con,itm=ItemLocation,C_Container,C_Item
 local old=C_AuctionHouse;local api=setmetatable({},{__index=old});C_AuctionHouse=api
 local printed={};local oldPrint=M.Print;M.Print=function(_,t) printed[#printed+1]=t end
 local ok,err=pcall(function()
  ItemLocation={CreateFromBagAndSlot=function() return {} end}
  C_Container={GetContainerItemInfo=function() return {itemID=9100,hyperlink='raiment',stackCount=1} end}
  api.IsThrottledMessageSystemReady=function() return true end
  local key={itemID=9100,itemSuffix=7,itemLevel=0,battlePetSpeciesID=0}
  api.GetItemKeyFromItem=function() return key end
  api.GetItemKeyInfo=function() return {isCommodity=false} end
  api.GetAvailablePostCount=function() return 0 end
  local valid=true;api.IsSellItemValid=function() return valid end
  local row={bag=0,slot=1,itemID=9100,itemLink='raiment',name='Vital Raiment of the Whale',quantity=1,marketKey='9100:s7'}
  local b,e=M.readBag(M,row)
  assert(b and b.max==1,'AH accepts it: postable, got '..tostring(e))
  valid=false;C_Item={IsBound=function() return true end}
  local sent;api.HasSearchResults=function() return false end;api.SendSearchQuery=function(k) sent=k end
  M.sellingRows={row};M:SetView('selling');M.ahOpen=true
  M:CheckPost(row);M:CheckPost(row)
  local n=0;for _,t in ipairs(printed) do if t:find('soulbound',1,true) then n=n+1 end end
  assert(n==1,'reason said once, got '..n)
  assert(M.postQuote and M.postQuote.blocked,'price check still runs')
  advance(1);M:PumpQueue();assert(sent,'live prices still searched')
 end)
 C_AuctionHouse=old;ItemLocation=loc;C_Container=con;C_Item=itm;M.Print=oldPrint;M.sellBlockedSaid=nil
 if not ok then error(err,0) end
end)
end
