return function(M,check,jobs,advance,emit)
-- 1.10.0 Auctionator-style buy view in Shopping, with chain buying and warnings.
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
 M.ahOpen=true;M:CancelRequests('test');M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil;M.queue.nextSend=0
 M.execution={state='idle',message='idle'};M.db.pending={};M.db.quoteGuardUntil=0;M.selectedRow=nil;M.shopBuy=nil
 M.db.settings.maxQuantity=5000
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
local function answer(com,key) M:PumpQueue();emit(com and 'COMMODITY_SEARCH_RESULTS_UPDATED' or 'ITEM_SEARCH_RESULTS_UPDATED',key);jobs() end
local function run(fn,...) local restore={...};local ok,err=pcall(fn);for _,r in ipairs(restore) do r() end;if not ok then error(err,0) end end
local boar={{unitPrice=158,quantity=390,numOwnerItems=0},{unitPrice=160,quantity=947,numOwnerItems=0},{unitPrice=161,quantity=324,numOwnerItems=0}}

check('1.10 Clicking a Shopping result opens the buy view with live price tiers',function()
 reset();local log,restoreAH=fakeAH(true,boar)
 run(function()
  M.browseRows={{marketKey=769,itemID=769,name='Chunk of Boar Meat',floor=158,quantity=2473,status='LIVE BROWSE'}}
  M:RenderUI();local s=M.shopScreen;local r=s.rows[1];assert(r:IsShown())
  r.scripts.OnClick(r);answer(true,769);M:RenderUI()
  assert(M.shopBuy and M.shopBuy.commodity and #M.shopBuy.rows==3)
  assert(s.buyView:IsShown() and not s.results:IsShown() and not s.buy:IsShown(),'buy view replaces results')
  local v=s.buyView
  assert(v.rows[1]:IsShown() and v.rows[3]:IsShown() and not v.rows[4]:IsShown())
  assert(v.rows[2].c[3]:GetText()=='947' and v.qty:GetText()=='1')
  assert(v.unit:GetText()==M:Coins(158) and v.total:GetText()==M:Coins(158) and v.buyNow.enabled)
  -- Clicking the third tier selects all three; prices add up across tiers.
  v.rows[3].scripts.OnClick(v.rows[3]);M:RenderUI()
  assert(M.shopBuy.quantity==1661 and v.qty:GetText()=='1661')
  assert(v.rows[1].sel.shown and v.rows[3].sel.shown)
  local total=390*158+947*160+324*161
  assert(v.total:GetText()==M:Coins(total) and v.unit:GetText()==M:Coins(math.ceil(total/1661)))
  -- Typing a quantity, capped at what is listed.
  v.qty.text='400';v.qty.scripts.OnTextChanged(v.qty,true);M:RenderUI()
  assert(M.shopBuy.quantity==400 and v.total:GetText()==M:Coins(390*158+10*160))
  assert(v.rows[2].sel.shown and not v.rows[3].sel.shown)
  M:ShopBuySetQuantity(99999);assert(M.shopBuy.quantity==1661)
  -- Back returns to the results.
  M:ShopBuyClose();M:RenderUI();assert(not s.buyView:IsShown() and s.results:IsShown())
 end,restoreAH)
end)

check('1.10 Commodity Buy Now: quote, confirm popup, ledger, then refresh keeping quantity (chain buy)',function()
 reset();local log,restoreAH=fakeAH(true,boar);local restoreP=stubPopups()
 run(function()
  M:ShopBuyOpen({marketKey=769,name='Chunk of Boar Meat'});answer(true,769)
  M:ShopBuySetQuantity(20);M:ShopBuyNow()
  assert(log[#log]=='quote:769:20' and M.execution.state=='quoting' and #popups==0)
  emit('COMMODITY_PRICE_UPDATED',158,3160)
  assert(M.execution.state=='quoted' and #popups==1 and popups[1].text:find('Confirm purchase of 20 x Chunk of Boar Meat',1,true))
  assert(not popups[1].text:find('increased',1,true))
  advance(10);M:ExecutionTick();assert(M.execution.state=='quoted','15 s to confirm from the shop')
  popups[1].data.accept();assert(log[#log]=='confirm:769:20' and M.execution.state=='pending')
  M:RenderUI();assert(not M.shopScreen.buyView.buyNow.enabled,'no second buy while pending')
  emit('COMMODITY_PURCHASE_SUCCEEDED');assert(M.execution.state=='complete')
  local lot=M.db.inventory[M:InventoryKey(769)];assert(lot.quantity==20 and lot.cost==3160)
  assert(M.shopBuy.searching and M.shopBuy.quantity==20,'listing refreshes, quantity kept')
  answer(true,769);M:RenderUI()
  local v=M.shopScreen.buyView
  assert(v.buyNow.enabled and v.status:GetText():find('Bought 20 x Chunk of Boar Meat',1,true))
  -- Chain: press Buy Now again straight away.
  M:ShopBuyNow();assert(log[#log]=='quote:769:20')
 end,restoreAH,restoreP)
end)

check('1.10 Warnings: price increased, wide price range, cancel discards the quote',function()
 reset();local log,restoreAH=fakeAH(true,boar);local restoreP=stubPopups()
 run(function()
  M:ShopBuyOpen({marketKey=769,name='Chunk of Boar Meat'});answer(true,769)
  M:ShopBuySetQuantity(10);M:ShopBuyNow()
  emit('COMMODITY_PRICE_UPDATED',170,1700)
  assert(M.execution.state=='quoted' and popups[1].text:find('The price has increased!',1,true),'shown, not silently rejected')
  popups[1].data.cancel();assert(M.execution.state=='invalid' and log[#log]=='cancel' and not M:HasUnresolvedPurchase())
  M:RenderUI();local v=M.shopScreen.buyView
  assert(not v.buyNow.enabled and v.status:GetText():find('Wait',1,true),'commodity guard after a cancelled quote')
  advance(11);M:RenderUI();assert(v.buyNow.enabled)
  -- 50%+ spread between cheapest and dearest unit asks first.
  M.shopBuy.rows={{unit=100,quantity=5,total=500},{unit=160,quantity=5,total=800}};M.shopBuy.max=10
  M:ShopBuySetQuantity(8);M:RenderUI();assert(v.status:GetText():find('CAREFUL',1,true))
  local n=#log;M:ShopBuyNow();assert(#log==n and popups[2].text:find('CAREFUL',1,true))
  popups[2].data.accept();assert(log[#log]=='quote:769:8')
 end,restoreAH,restoreP)
end)

check('1.10 Item buy view: pick a listing, Buy Now asks "Paying", buys that auction, then refreshes',function()
 reset()
 local key={itemID=4500,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0}
 local rows={{auctionID=11,quantity=1,buyoutAmount=900,itemKey=key},{auctionID=12,quantity=5,buyoutAmount=2500,itemKey=key}}
 local log,restoreAH=fakeAH(false,rows);local restoreP=stubPopups()
 local oldItem=C_Item;C_Item={GetItemMaxStackSizeByID=function() return 20 end}
 run(function()
  M:ShopBuyOpen({marketKey=4500,name='Silk Cloth Bag'});answer(false,key);M:RenderUI()
  local v=M.shopScreen.buyView
  assert(M.shopBuy.commodity==false and not v.qty:IsShown() and v.itemHint:IsShown())
  -- Cheapest per item first, like Auctionator's unit-price sort.
  assert(v.rows[1].c[1]:GetText()==M:Coins(2500) and v.rows[1].c[2]:GetText()==M:Coins(500) and v.rows[1].c[3]:GetText()=='5')
  assert(v.rows[2].c[1]:GetText()==M:Coins(900) and v.rows[2].c[2]:GetText()=='')
  v.rows[2].scripts.OnClick(v.rows[2]);M:RenderUI();assert(v.total:GetText()==M:Coins(900) and v.rows[2].sel.shown and not v.rows[1].sel.shown)
  v.rows[1].scripts.OnClick(v.rows[1]);M:RenderUI();assert(v.total:GetText()==M:Coins(2500) and v.rows[1].sel.shown)
  M:ShopBuyNow();assert(popups[1].text:find('Paying',1,true) and popups[1].text:find('5 x Silk Cloth Bag',1,true))
  popups[1].data.accept();assert(log[#log]=='bid:12:2500' and M.execution.state=='pending')
  emit('AUCTION_HOUSE_PURCHASE_COMPLETED',12);assert(M.execution.state=='complete' and M.shopBuy.searching)
  assert(M.db.inventory[M:InventoryKey(4500)].quantity==5)
 end,restoreAH,restoreP,function() C_Item=oldItem end)
end)

check('1.10 Limits block Buy Now with a plain reason',function()
 reset();local log,restoreAH=fakeAH(true,boar)
 local oldMoney=GetMoney
 run(function()
  M:ShopBuyOpen({marketKey=769,name='Chunk of Boar Meat'});answer(true,769)
  M.db.settings.maxQuantity=20;M:ShopBuySetQuantity(50);M:RenderUI();local v=M.shopScreen.buyView
  assert(not v.buyNow.enabled and v.status:GetText():find('quantity limit (20)',1,true))
  M.db.settings.maxQuantity=5000;GetMoney=function() return 100 end;M:RenderUI()
  assert(not v.buyNow.enabled and v.status:GetText():find('Not enough gold',1,true))
  local n=#log;M:ShopBuyNow();assert(#log==n)
  GetMoney=oldMoney;M:RenderUI();assert(v.buyNow.enabled)
  -- A new search closes the buy view.
  M:ShopSearch('linen');assert(M.shopBuy==nil)
 end,restoreAH,function() GetMoney=oldMoney end)
end)
end
