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
end
