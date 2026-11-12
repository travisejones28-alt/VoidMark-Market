local _,M=...
local function whole(n,max) return M:Finite(n,1,max) and n%1==0 end
local function usable(self)
 return not self.persistenceBlocked and self:CanUseAuctionHouse() and self:ThrottleReady() and not (InCombatLockdown and InCombatLockdown())
end
function M:AskTrade(message,accept)
 if not usable(self) then self:Print('Open the AH and wait for it to be ready');return end
 if not StaticPopupDialogs or not StaticPopup_Show then self:Print('Confirmation dialog unavailable');return end
 StaticPopupDialogs.VOIDMARKMARKET_TRADE=StaticPopupDialogs.VOIDMARKMARKET_TRADE or {
  text='%s',button1=ACCEPT or 'Confirm',button2=CANCEL or 'Cancel',timeout=10,whileDead=false,
  hideOnEscape=true,preferredIndex=3,OnAccept=function(_,action) if type(action)=='function' then action() end end}
 StaticPopup_Show('VOIDMARKMARKET_TRADE',message,nil,accept)
end
function M:ShopSelected(row)
 local key,id,s,l,p=self:ParseKey(row and row.marketKey)
 if not key or not self.ahOpen then self:Print('Select an item with the Auction House open');return end
 local m=self.db.market[key] or {marketKey=key,itemID=id,itemSuffix=s,itemLevel=l,battlePetSpeciesID=p,
  name=row.name or 'Item '..id,latest={},observations=0}
 self:SelectOpportunity({marketKey=key,kind='shopping',shoppingMarket=m,pass=true,target=row.target})
end
function M:ReviewRegularPurchase()
 local x=self.execution;if not x.live or x.state~='ready' or x.commodity then return end
 self:AskTrade('Buy '..x.live.quantity..' x '..x.market.name..' for '..self:Money(x.live.cost)..'?',function()
  if self.execution==x and x.state=='ready' and usable(self) then self:ExecuteClicked() end
 end)
end
function M:LiveNameSearch(text)
 text=(text or ''):match('^%s*(.-)%s*$')
 if #text<2 or not self.ahOpen then self:Print('Open the AH and enter at least two characters');return end
 if not C_AuctionHouse.GetBrowseResults then self:Print('Live browse unavailable');return end
 self.shoppingListMode=false;self.shoppingSearchStatus='Searching the Auction House for '..text..'...';self.browseRows={};self:RefreshUI()
 local q={searchString=text,sorts={},filters={},itemClassFilters={}}
 if self.ApplyLevelQuery then self:ApplyLevelQuery(q) end
 local pages,done,fail=0
 local token={};self.nameSearch=token
 fail=function(e) self.shoppingSearchStatus='Search failed: '..tostring(e);self:Print(e);self:RefreshUI() end
 done=function()
  if self.nameSearch~=token or self.view~='browse' or (self.db.settings.filter or ''):match('^%s*(.-)%s*$')~=text then return end
  pages=pages+1
  local result=C_AuctionHouse.GetBrowseResults() or {};local out={}
  for i=1,math.min(5000,#result) do
   local b=result[i];local k=b.itemKey
   local key=k and self:Key(k.itemID,k.itemSuffix,k.itemLevel,k.battlePetSpeciesID)
   if key and (not self.LevelAllowed or self:LevelAllowed(k.itemID)) then
    if self.RecordLiveFloor then self:RecordLiveFloor(key,b.minPrice,b.totalQuantity) end
    local m=self.db.market[key];local info=C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(k)
    out[#out+1]={marketKey=key,itemID=k.itemID,name=(info and info.itemName) or (m and m.name) or ('Item '..k.itemID),
     floor=b.minPrice or 0,quantity=tonumber(b.totalQuantity),fair=m and m.fairValue or 0,modelReady=self:CanEstimateResale(m),confidence=m and m.confidence or 'Unknown',status='LIVE BROWSE'}
   end
  end
  local more=self.BrowseNeedsMore and self:BrowseNeedsMore(pages) and self:QueueBrowseMore('browse-name',done,fail)
  self.shoppingSearchStatus=more and ('Searching the Auction House for '..text..'... page '..(pages+1)) or #out==0 and ('No auctions found for '..text..'. Try another name.') or nil
  self:CancelJob('browse');self.browseRows=out;if pages==1 then self.selectedRow=nil end;self.page=1;self:SortBrowseRows();self:RefreshUI()
 end
 self:QueueRequest({id='browse-name',kind='browse',query=q,priority=50,done=done,fail=fail})
end
function M:ReadBagSlot(r) return self.readBag(self,r) end
-- The bag list on Selling can be out of date (items moved, stacked, looted
-- or posted since it was built). Find the same item in its current slot.
function M:FindBagItem(r)
 local get=C_Container and C_Container.GetContainerItemInfo
 local slots=C_Container and C_Container.GetContainerNumSlots
 if not get or not slots then return end
 local loose
 for bag=0,4 do
  local ok,n=pcall(slots,bag)
  for slot=1,(ok and tonumber(n) or 0) do
   local b=get(bag,slot)
   if type(b)=='table' and b.itemID==r.itemID and not b.isBound then
    if b.hyperlink==r.itemLink and not b.isLocked then return bag,slot end
    if not loose and not b.isLocked and r.marketKey~=nil and self:LinkIdentity(b.hyperlink,b.itemID)==r.marketKey then loose={bag,slot,b.hyperlink} end
   end
  end
 end
 if loose then return loose[1],loose[2],loose[3] end
end
local function readBag(self,r)
 if not usable(self) or not r or not r.slot or not ItemLocation or not C_Container then return nil,'Open the AH and select a bag item' end
 local b=C_Container.GetContainerItemInfo(r.bag,r.slot)
 if b and b.isLocked and b.hyperlink==r.itemLink then return nil,'Item is locked for a moment' end
 if not b or not b.hyperlink or b.hyperlink~=r.itemLink or b.itemID~=r.itemID or b.isBound then
  local bag,slot,link=self:FindBagItem(r)
  self.bagsDirty=true -- rebuild the list on the next tick
  if not bag then return nil,'That item is no longer in your bags' end
  r.bag,r.slot=bag,slot;if link then r.itemLink=link end
  b=C_Container.GetContainerItemInfo(bag,slot)
  if not b or b.hyperlink~=r.itemLink or b.isBound then return nil,'That item is no longer in your bags' end
 end
 if b.isLocked then return nil,'Item is locked for a moment' end
 local loc=ItemLocation:CreateFromBagAndSlot(r.bag,r.slot)
 local A=C_AuctionHouse;local k=A.GetItemKeyFromItem and A.GetItemKeyFromItem(loc)
 if not k or k.itemID~=b.itemID then return nil,'Exact auction identity unavailable' end
 local commodity=self:IsCommodity(k)
 if commodity==nil and A.GetItemCommodityStatus and Enum and Enum.ItemCommodityStatus then
  local status=A.GetItemCommodityStatus(loc)
  if status==Enum.ItemCommodityStatus.Commodity then commodity=true elseif status==Enum.ItemCommodityStatus.Item then commodity=false end
 end
 if commodity==nil then return nil,'Waiting for item classification' end
 local n=A.GetAvailablePostCount and A.GetAvailablePostCount(loc)
 if not whole(n,1e9) then return nil,'Item cannot currently be posted' end
 -- Like Auctionator: one post can use every unit in the bags (items become
 -- several auctions), capped by what the AH says can be posted.
 local total=self:BagCount(r.marketKey,b.itemID)
 return {loc=loc,k=k,commodity=commodity,max=math.max(1,math.min(n,total>0 and total or n))}
end
M.readBag=readBag
function M:CheckPost(row)
 self.postQuote=nil
 local b,e=readBag(self,row)
 if not b then
  -- Right after a post the slot is briefly locked; try again shortly.
  if e and e:find('locked',1,true) and (self.sellRetry or 0)<10 then
   self.sellRetry=(self.sellRetry or 0)+1;self.sellCheckAt=GetTime()+0.2;self.sellCheckRow=row;return
  end
  self.sellRetry=nil;self:Print(e);return
 end
 self.sellRetry=nil
 local draft={row=row,k=b.k,commodity=b.commodity,deadline=GetTime()+10};self.postQuote=draft
 self:Search(b.k,60,function(result)
  if self.postQuote~=draft or self.view~='selling' then return end
  self.sellDupes=nil
  -- A late live answer replaces a price we filled from the last scan.
  local replaceFallback=draft.fallback and draft.fallbackUnit and self:GetPostPrice()==draft.fallbackUnit
  draft.fallback=nil;draft.reason=nil
  draft.at=result.received;draft.floor=result.rows[1] and result.rows[1].unit;draft.listings=result.all or {}
  local unit,clamped,why=self:SuggestPostUnit(row,draft.floor,draft.commodity);draft.atMinimum=clamped;draft.minWhy=why
  if (self:PostPriceEmpty() or replaceFallback) and unit then self:SetPostPrice(unit) end
  local now=readBag(self,row);draft.max=now and now.max;draft.commodity=now and now.commodity
  if now and self.postQty and not draft.qtyTouched then self.postQty:SetText(tostring(now.max)) end
  self:RefreshUI()
 end,function(e)
  if self.postQuote~=draft then return end
  -- An earlier search for this item is still running: re-check when it ends.
  if type(e)=='string' and e:find('already running',1,true) and (self.sellDupes or 0)<10 then
   self.sellDupes=(self.sellDupes or 0)+1;self.sellCheckAt=GetTime()+1;self.sellCheckRow=row;return
  end
  self:UseScanPrice(draft,e)
 end,nil,true)
end
-- The live check failed or did not answer: price from the last scan instead of
-- leaving the item stuck on "Checking live price..." with an empty price.
function M:UseScanPrice(draft,reason)
 if self.postQuote~=draft or draft.at then return end
 draft.at=GetTime();draft.fallback=true;draft.reason=reason;draft.listings={}
 local unit,clamped,why=self:SuggestPostUnit(draft.row,nil,draft.commodity);draft.atMinimum=clamped;draft.minWhy=why
 if unit and self:PostPriceEmpty() then self:SetPostPrice(unit);draft.fallbackUnit=unit end
 local why=reason and (' ('..tostring(reason)..')') or ''
 self:Print(unit and ('Live price did not answer'..why..'; using the last scan price. Check it before posting.')
  or ('Live price did not answer'..why..' and there is no scan price. Enter a price.'))
 self:RefreshUI()
end
local function postTerms(self,row,n,unit,duration)
 if self.tradePending then return nil,'A previous request is awaiting its result' end
 local q=self.postQuote
 if not q or not q.at or GetTime()-q.at>60 or self.view~='selling' or not self.selectedRow or
  self.selectedRow.bag~=row.bag or self.selectedRow.slot~=row.slot or self.selectedRow.itemLink~=row.itemLink or
  q.row.bag~=row.bag or q.row.slot~=row.slot or q.row.itemLink~=row.itemLink then return nil,'Select the item and check its live price again' end
 local b,e=readBag(self,row);if not b then return nil,e end
 if not self:SameKey(b.k,q.k) or not whole(n,b.max) or not whole(unit,1e12) or unit*n>1e12 or not whole(duration,3) then return nil,'Invalid price, duration, quantity or item variant' end
 local A=C_AuctionHouse;local dep=b.commodity and A.CalculateCommodityDeposit or A.CalculateItemDeposit
 if not dep or not (b.commodity and A.PostCommodity or not b.commodity and A.PostItem) then return nil,'Posting API unavailable' end
 local cost=dep(b.commodity and row.itemID or b.loc,duration,n)
 if not self:Finite(cost,0,1e12) or not GetMoney or GetMoney()<cost then return nil,'Deposit unknown or unaffordable' end
 b.deposit=cost;return b
end
function M:ReviewPost(row,n,unit,duration)
 if not row then self:Print('Select a bag item');return end
 local b,e=postTerms(self,row,n,unit,duration);if not b then self:Print(e);return end
 if not b.commodity and unit%100~=0 then
  unit=self:WholeSilver(unit);self:SetPostPrice(unit)
  self:Print('Items post in whole silver on this server; posting at '..self:Money(unit)..'.')
 end
 local q=self.postQuote
 local market=q.floor and self:Money(q.floor)..' / unit' or 'no competing listings'
 local function post()
  local now,reason=postTerms(self,row,n,unit,duration)
  if not now or self.postQuote~=q or now.deposit~=b.deposit then self:Print(reason or 'Quote changed; review again');return end
  self.postQuote=nil;self.tradePending='post';self.postingRow=row
  row.postedUnit=unit;row.postedQuantity=n;row.postedDuration=duration;row.postHistoryRecorded=nil
  local A=C_AuctionHouse;local ok,pending
  if now.commodity then ok,pending=pcall(A.PostCommodity,now.loc,duration,n,unit)
  else ok,pending=pcall(A.PostItem,now.loc,duration,n,nil,unit) end
  if not ok then self.tradePending=nil;self.postingRow=nil;self:Print('Posting failed: '..tostring(pending));return end
  -- 1.22.14: remember the post price right away (commodity posts don't always
  -- send AUCTION_HOUSE_AUCTION_CREATED) and reload your auctions shortly after,
  -- so sale alerts know the price of what you just listed.
  if self.RecordPostHistory then self:RecordPostHistory(row) end
  if C_Timer and C_Timer.After and self.RequestOwnedAuctionsDiagnostic then
   C_Timer.After(2.5,function() if self.ahOpen then pcall(self.RequestOwnedAuctionsDiagnostic,self) end end)
  end
  if pending then
   local f=AuctionHouseFrame and (now.commodity and AuctionHouseFrame.CommoditiesSellFrame or AuctionHouseFrame.ItemSellFrame)
   if f and f.CachePendingPost then
    if now.commodity then f:CachePendingPost(now.loc,duration,n,unit) else f:CachePendingPost(now.loc,duration,n,nil,unit) end
   end
  end
 end
 -- Default asks first. With "Ask before posting" off, the Post click itself
 -- is the confirmation (like Auctionator); the same checks still run.
 if self.db.settings.confirmPosts==false then return post() end
 self:AskTrade(('Post %d x %s at %s each (%s total)?\nCompetition: %s. Deposit: %s. Duration: %dh.'):format(n,row.name,self:Money(unit),self:Money(n*unit),market,self:Money(b.deposit),({2,8,24})[duration]),post)
end
local function cancelFee(self,r)
 if not usable(self) or self.tradePending or not r or not whole(r.auctionID,1e15) then return nil,'Select a current owned auction' end
 local A=C_AuctionHouse;if not A.GetOwnedAuctions or not A.GetCancelCost or not A.CancelAuction or not A.CanCancelAuction then return nil,'Cancellation API unavailable' end
 for _,info in ipairs(A.GetOwnedAuctions() or {}) do
  if info.auctionID==r.auctionID and self:SameKey(info.itemKey,r.itemKey) then
   if not A.CanCancelAuction(r.auctionID) then return nil,'Auction can no longer be canceled' end
   local fee=A.GetCancelCost(r.auctionID)
   if self:Finite(fee,0,1e12) and GetMoney and GetMoney()>=fee then return fee end
   return nil,'Cancellation cost unknown or unaffordable'
  end
 end
 return nil,'Auction no longer owned; refresh My Auctions'
end
function M:ReviewCancel(row)
 local fee,e=cancelFee(self,row);if not fee then self:Print(e);return end
 self:AskTrade(('Cancel #%s: %s x %d?\nFee: %s. The original deposit may be lost.'):format(row.auctionID,row.name,row.quantity,self:Money(fee)),function()
  if self.view~='my auctions' or self.selectedRow~=row then return end
  local now,reason=cancelFee(self,row);if now~=fee then self:Print(reason or 'Fee changed; review again');return end
  self.tradePending='cancel';local ok,err=pcall(C_AuctionHouse.CancelAuction,row.auctionID)
  if not ok then self.tradePending=nil;self:Print('Cancel failed: '..tostring(err)) end
 end)
end
-- Readable AH error: look the code up in the client's own Enum.AuctionHouseError.
function M:AuctionErrorName(code)
 local n=tonumber(code)
 local enum=Enum and Enum.AuctionHouseError
 if n and type(enum)=='table' then
  for name,value in pairs(enum) do if value==n then
   return (name:gsub('(%l)(%u)','%1 %2'))..' ('..n..')'
  end end
 end
 return tostring(code)
end
for _,event in ipairs({'AUCTION_CANCELED','AUCTION_HOUSE_AUCTION_CREATED','AUCTION_HOUSE_SHOW_ERROR','AUCTION_HOUSE_CLOSED'}) do
 M:RegisterHandler(event,function(self,e,code)
  if self.tradePending and e=='AUCTION_HOUSE_SHOW_ERROR' then
   local what=self.tradePending=='post' and self.postingRow and (' posting '..tostring(self.postingRow.name or 'item')) or ''
   self:Print('AH rejected the request'..what..': '..self:AuctionErrorName(code))
  end
  if e=='AUCTION_HOUSE_CLOSED' then self.postQuote=nil
   if StaticPopup_Hide then StaticPopup_Hide('VOIDMARKMARKET_TRADE') end
  end
  if self.tradePending and (e=='AUCTION_HOUSE_CLOSED' or e=='AUCTION_HOUSE_SHOW_ERROR' or
   (e=='AUCTION_CANCELED' and self.tradePending=='cancel') or (e=='AUCTION_HOUSE_AUCTION_CREATED' and self.tradePending=='post')) then self.tradePending=nil end
  self:RefreshUI()
 end)
end
