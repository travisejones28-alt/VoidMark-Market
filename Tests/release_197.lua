return function(M,check,jobs,advance,emit)
-- 1.9.7 Selling never stays stuck on "Checking live price..." with an empty price.
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
 M.ahOpen=true;M:CancelRequests('test');M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil;M.queue.nextSend=0
 M.execution={state='idle',message='idle'};M.selectedRow=nil;M.postQuote=nil;M.tradePending=nil
 M:InitializeUI();M:SetView('selling')
end
-- Linen Cloth is a commodity that was already searched this session.
local function linenAH(opts)
 local old=C_AuctionHouse;local api=setmetatable({},{__index=old});C_AuctionHouse=api
 api.IsThrottledMessageSystemReady=function() return true end
 api.GetItemKeyFromItem=function() return {itemID=2589,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0} end
 api.GetItemKeyInfo=function() return {isCommodity=true} end
 api.GetAvailablePostCount=function() return 70 end
 api.HasSearchResults=function() return opts.has end
 api.RefreshCommoditySearchResults=function() opts.refreshed=(opts.refreshed or 0)+1 end -- answers with no event
 api.SendSearchQuery=function() opts.sent=(opts.sent or 0)+1 end
 api.HasFullCommoditySearchResults=function() return opts.full end
 api.GetNumCommoditySearchResults=function() return opts.full and 1 or 0 end
 api.GetCommoditySearchResultInfo=function() return {unitPrice=50,quantity=200,numOwnerItems=0} end
 api.CalculateCommodityDeposit=function(_,_,n) return n end
 return old
end
local function setup(rowPrice)
 local loc,con=ItemLocation,C_Container
 ItemLocation={CreateFromBagAndSlot=function() return {} end}
 C_Container={GetContainerItemInfo=function() return {itemID=2589,hyperlink='linen',stackCount=70} end}
 local row={bag=0,slot=1,itemID=2589,itemLink='linen',name='Linen Cloth',quantity=70,marketKey=2589,price=rowPrice}
 M.sellingRows={row}
 return row,function() ItemLocation=loc;C_Container=con end
end
local function capture() local printed={};local old=M.Print;M.Print=function(_,s) printed[#printed+1]=s end;return printed,function() M.Print=old end end
local function tick(n,step) for _=1,n do advance(step or 1);M:PumpQueue();jobs();M:SellTick() end end

check('1.9.7 A refresh that answers without an event still fills the price (Linen Cloth)',function()
 reset();local opts={has=true,full=true};local oldAH=linenAH(opts);local row,restore=setup(80);local printed,unprint=capture()
 local ok,err=pcall(function()
  M:SelectSellRow(row,true);tick(1,0.1)
  assert(M.postQuote and not M.postQuote.at,'check started')
  assert(opts.refreshed==1,'existing results are refreshed, not re-queried')
  tick(3)
  assert(M.postQuote.at and not M.postQuote.fallback,'client results read after a short wait')
  assert(M:GetPostPrice()==49,'price = lowest (50) minus 1 copper undercut, got '..tostring(M:GetPostPrice()))
 end)
 unprint();restore();C_AuctionHouse=oldAH;if not ok then error(err,0) end
end)

check('1.9.7 No live answer: last scan price after 10 s, and a late live answer replaces it',function()
 reset();local opts={has=false,full=false};local oldAH=linenAH(opts);local row,restore=setup(80);local printed,unprint=capture()
 local ok,err=pcall(function()
  M:SelectSellRow(row,true);tick(1,0.1)
  assert(M.postQuote and not M.postQuote.at and opts.sent==1)
  tick(5)
  assert(not M.postQuote.at,'still waiting before the deadline')
  M:PostClicked()
  assert(printed[#printed]:find('Still checking',1,true),'Post during the check explains itself')
  tick(6)
  assert(M.postQuote and M.postQuote.at and M.postQuote.fallback,'falls back after 10 seconds')
  assert(M:GetPostPrice()==80,'uses the last scan price')
  assert(printed[#printed]:find('last scan price',1,true))
  M:RefreshUI();M:RenderUI();local info=M.sellScreen.info:GetText();assert(info:find('did not answer',1,true),'info: '..tostring(info))
  -- The live answer arrives later: it replaces the scan price we filled in.
  opts.full=true;emit('COMMODITY_SEARCH_RESULTS_UPDATED',2589);jobs()
  assert(not M.postQuote.fallback and M:GetPostPrice()==49,'late live price replaces the fallback')
 end)
 unprint();restore();C_AuctionHouse=oldAH;if not ok then error(err,0) end
end)

check('1.9.7 A price you typed is never replaced by a late live answer',function()
 reset();local opts={has=false,full=false};local oldAH=linenAH(opts);local row,restore=setup(80);local printed,unprint=capture()
 local ok,err=pcall(function()
  M:SelectSellRow(row,true);tick(1,0.1);tick(11)
  assert(M.postQuote.fallback and M:GetPostPrice()==80)
  M:SetPostPrice(123)
  opts.full=true;emit('COMMODITY_SEARCH_RESULTS_UPDATED',2589);jobs()
  assert(M:GetPostPrice()==123,'typed price kept')
 end)
 unprint();restore();C_AuctionHouse=oldAH;if not ok then error(err,0) end
end)
check('1.9.8 AH errors show the client error name',function()
 local old=Enum;Enum=setmetatable({AuctionHouseError={DatabaseError=10,NotEnoughMoney=0}},{__index=old})
 local ok,err=pcall(function()
  assert(M:AuctionErrorName(10)=='Database Error (10)',M:AuctionErrorName(10))
  assert(M:AuctionErrorName(99)=='99')
 end)
 Enum=old;if not ok then error(err,0) end
end)
check('1.9.10 A search already running is waited for, not replaced by the scan price',function()
 reset();local opts={has=false,full=false};local oldAH=linenAH(opts);local row,restore=setup(80);local printed,unprint=capture()
 local ok,err=pcall(function()
  M.queue.dedupe['search:2589']={id='search:2589'} -- an earlier search for Linen is still running
  M:SelectSellRow(row,true)
  assert(M.postQuote and not M.postQuote.at and M.sellCheckAt,'re-check scheduled')
  for _,s in ipairs(printed) do assert(not s:find('did not answer',1,true),'no fallback on a running search') end
  M.queue.dedupe={};tick(2)
  assert(opts.sent==1,'checked again once the earlier search ended')
 end)
 unprint();restore();C_AuctionHouse=oldAH;M.sellDupes=nil;if not ok then error(err,0) end
end)

check('1.9.11 Regular items are priced and posted in whole silver; commodities keep copper',function()
 reset();local printed,unprint=capture()
 local loc,con=ItemLocation,C_Container
 local old=C_AuctionHouse;local api=setmetatable({},{__index=old});C_AuctionHouse=api
 local ok,err=pcall(function()
  ItemLocation={CreateFromBagAndSlot=function() return {} end}
  C_Container={GetContainerItemInfo=function() return {itemID=9000,hyperlink='belt',stackCount=1} end}
  api.IsThrottledMessageSystemReady=function() return true end
  api.GetItemKeyFromItem=function() return {itemID=9000,itemSuffix=5,itemLevel=0,battlePetSpeciesID=0} end
  api.GetItemKeyInfo=function() return {isCommodity=false} end
  api.GetAvailablePostCount=function() return 1 end
  api.HasSearchResults=function() return false end;local cur;api.SendSearchQuery=function(k) cur=k end
  api.HasFullItemSearchResults=function() return true end;api.GetNumItemSearchResults=function() return 1 end
  api.GetItemSearchResultInfo=function() return {auctionID=1,buyoutAmount=1600,quantity=1,itemKey={itemID=9000,itemSuffix=5,itemLevel=0,battlePetSpeciesID=0}} end
  api.CalculateItemDeposit=function() return 10 end
  local calls={};api.PostItem=function(_,d,n,bid,unit) calls[#calls+1]={bid=bid,unit=unit};return false end
  local row={bag=0,slot=1,itemID=9000,itemLink='belt',name='Willow Belt of the Eagle',quantity=1,marketKey='9000:s5'}
  M.sellingRows={row};M:SetView('selling');M.db.settings.confirmPosts=false
  M:SelectSellRow(row,true);for _=1,3 do advance(1);M:PumpQueue();if cur then local k=cur;cur=nil;emit('ITEM_SEARCH_RESULTS_UPDATED',k);jobs() end end
  assert(M.postQuote and M.postQuote.at and M.postQuote.floor==1600,'live lowest 16s')
  assert(M:GetPostPrice()==1500,'item undercut lands on whole silver (15s), got '..tostring(M:GetPostPrice()))
  M:SetPostPrice(1599);M:PostClicked()
  assert(#calls==1 and calls[1].unit==1500 and calls[1].bid==nil,'typed 15s 99c posts as 15s with no bid')
  assert(printed[#printed]:find('whole silver',1,true))
  -- Commodities keep copper precision.
  assert(M:SuggestPostUnit({marketKey=2589},1600,true)==1599)
  assert(M:SuggestPostUnit({marketKey=9000},1550,false)==1500)
  assert(M:WholeSilver(40)==100,'never below 1 silver')
 end)
 C_AuctionHouse=old;ItemLocation=loc;C_Container=con;M.db.settings.confirmPosts=nil;unprint()
 if not ok then error(err,0) end
end)
end
