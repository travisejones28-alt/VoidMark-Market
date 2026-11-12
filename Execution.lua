local _,M=...
M.execution={state='idle',message='Select an opportunity and revalidate'}
-- A buy still in flight (sent, no result yet, at most ~15s) blocks the next
-- one. An item buy whose result never came ("unknown") no longer blocks
-- buying (Auctionator never blocks); its gold stays reserved until settled.
function M:HasUnresolvedPurchase()
  -- Commodity buys stay blocking: a repeat could buy a whole stack twice. An item
  -- buy is one unique auction, so an unknown one can't be bought twice.
  for _,p in pairs(self.db.pending) do if p.character==self.characterID and (p.status~='unknown' or p.commodity) then return true end end
  return false
end
function M:HasUnknownPurchase()
  for _,p in pairs(self.db.pending) do if p.character==self.characterID then return true end end
  return false
end
function M:SelectOpportunity(o)
  if self:HasUnresolvedPurchase() or self.execution.state=='quoting' or self.execution.state=='quoted' then self:Print('Resolve the current transaction first'); return end
  self.executionToken=(self.executionToken or 0)+1
  self.execution={state='selected',opportunity=o,market=self.db.market[o.marketKey] or o.shoppingMarket,token=self.executionToken,message='Choose a quantity, then click CHECK PRICE.'}
  self:SetView('execution')
end
function M:RevalidateSelected(quantity)
  local x=self.execution; if not x.market or self:HasUnresolvedPurchase() or x.state=='quoting' or x.state=='quoted' or x.state=='validating' then return end
  quantity=math.max(1,math.floor(tonumber(quantity) or 1)); quantity=math.min(quantity,self.db.settings.maxQuantity)
  if quantity<1 then x.message='Quantity limit is zero'; self:RefreshUI(); return end
  x.state='validating'; x.message='Waiting for fresh complete search results'; x.live=nil
  local requested=x
  self:Search(x.market,100,function(result)
    if M.execution~=requested then return end
    if not result.rows[1] then x.state='invalid'; x.message='No buyable auctions remain'; M:RefreshUI(); return end
    x.commodity=result.commodity
    local live={quantity=0,cost=0,received=result.received,at=result.at}
    if result.commodity then
      local left=quantity
      for _,r in ipairs(result.rows) do
        local take=math.min(left,r.quantity); live.quantity=live.quantity+take; live.cost=live.cost+take*r.unit; left=left-take
        if left==0 then break end
      end
      if left>0 then x.state='invalid'; x.message='Requested quantity no longer available'; M:RefreshUI(); return end
    else
      -- One click purchases exactly one complete auction, never an automatic loop.
      local best
      for _,r in ipairs(result.rows) do
        if r.quantity<=quantity and r.auctionID then best=r; break end
      end
      if not best then x.state='invalid'; x.message='No whole auction fits quantity limit'; M:RefreshUI(); return end
      live.quantity=best.quantity; live.cost=best.total; live.auctionID=best.auctionID
    end
    local vendor=x.opportunity.kind=='vendor'
    if vendor and GetItemInfo then
      local _,_,_,_,_,_,_,_,_,_,value=GetItemInfo(x.market.itemLink or x.market.itemID)
      x.market.vendorPrice=tonumber(value) or 0
    end
    live.economics=M:Economics(x.market,live.cost,live.quantity,x.opportunity.kind)
    local pass,why=M:CheckRisk(x.market,live.economics)
    if x.opportunity.target and live.cost>live.quantity*x.opportunity.target then pass=false;why[#why+1]='Above shopping target' end
    live.blocks=why; x.live=live; x.state=pass and 'ready' or 'invalid'
    x.message=pass and 'Fresh market validated; one transaction requires one click' or table.concat(why,'; ')
    M:RefreshUI()
  end,function(err) if M.execution==requested then x.state='invalid'; x.message=err; M:RefreshUI() end end,
    function() return M.execution==requested and requested.state=='validating' end)
  self:RefreshUI()
end
function M:ExecuteClicked()
  -- Called only by the EXECUTE button OnClick. No timer/event invokes this function.
  local x=self.execution
  if self.persistenceBlocked then self:Print('Database schema is newer than this addon; trading blocked'); return end
  if x.commodity and (self.db.quoteGuardUntil or 0)>time() then self:Print('Commodity guard: wait '..self:FormatDuration(self.db.quoteGuardUntil-time())); return end
  if not self:CanUseAuctionHouse() or not self:ThrottleReady() or self:HasUnresolvedPurchase() or x.state~='ready' or not x.live then return end
  if GetTime()-x.live.received>10 then x.state='stale'; x.message='Live prices expired; revalidate'; self:RefreshUI(); return end
  local pass,why=self:CheckRisk(x.market,x.live.economics)
  if not pass then x.state='invalid'; x.message=table.concat(why,'; '); self:RefreshUI(); return end
  local fn=x.commodity and C_AuctionHouse.StartCommoditiesPurchase or C_AuctionHouse.PlaceBid
  if type(fn)~='function' then x.state='invalid'; x.message='Purchase API unavailable'; self:RefreshUI(); return end
  if x.commodity and type(C_AuctionHouse.ConfirmCommoditiesPurchase)~='function' then x.state='invalid'; x.message='Confirmation API unavailable'; return end
  x.sent=GetTime()
  if x.commodity then
    x.state='quoting'; x.message='Waiting for quote; confirmation needs a second click'
    local ok,err=pcall(fn,x.market.itemID,x.live.quantity)
    if not ok then x.state='invalid'; x.message=tostring(err) end
  else
    self:ReservePurchase(x); x.state='pending'; x.message='Waiting for auction purchase result'
    local ok,err=pcall(fn,x.live.auctionID,x.live.cost)
    if not ok then self:ResolvePurchase(x.order,'failed','API rejected request: '..tostring(err)); x.state='invalid'; x.message=tostring(err) end
  end
  self:RefreshUI()
end
function M:ConfirmClicked()
  -- Called only by CONFIRM QUOTE OnClick. Events never confirm automatically.
  local x=self.execution
  if self.persistenceBlocked or not self:CanUseAuctionHouse() or x.state~='quoted' then return end
  if GetTime()-x.quotedAt>(x.quoteWindow or 5) then self:InvalidateQuote('Quote expired; revalidate'); return end
  if not self:ThrottleReady() then return end
  local pass,why=self:CheckRisk(x.market,x.live.economics)
  if not pass then self:InvalidateQuote(table.concat(why,'; ')); return end
  self:ReservePurchase(x); x.state='pending'; x.sent=GetTime(); x.message='Waiting for commodity result'
  local ok,err=pcall(C_AuctionHouse.ConfirmCommoditiesPurchase,x.market.itemID,x.live.quantity)
  if not ok then self:ResolvePurchase(x.order,'failed','Confirmation API rejected: '..tostring(err)); self:InvalidateQuote(tostring(err)) end
  self:RefreshUI()
end
function M:InvalidateQuote(reason)
  local x=self.execution
  if x.state=='quoting' or x.state=='quoted' then
    self.db.quoteGuardUntil=time()+10
    if C_AuctionHouse and C_AuctionHouse.CancelCommoditiesPurchase then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
  end
  x.state='invalid'; x.message=reason; self:RefreshUI()
end
function M:ExecutionTick()
  local x=self.execution
  if x.state=='ready' and GetTime()-x.live.received>10 then x.state='stale'; x.message='Live prices expired; revalidate'; self:RefreshUI()
  elseif x.state=='quoting' and GetTime()-x.sent>3 then self:InvalidateQuote('Quote request timed out')
  elseif x.state=='quoted' and GetTime()-x.quotedAt>(x.quoteWindow or 5) then self:InvalidateQuote('Quote expired')
  elseif x.state=='pending' and GetTime()-x.sent>15 then
    x.order.status='unknown'; x.order.evidence='Request sent, result not received'; x.state='unknown'
    x.message='Result uncertain; gold stays reserved. Check mailbox and reconcile in Ledger.'; self:RefreshUI()
  end
end
M:RegisterHandler('COMMODITY_PRICE_UPDATED',function(self,_,unit,total)
  local x=self.execution; if x.state~='quoting' or GetTime()-x.sent>3 then return end
  unit=tonumber(unit); total=tonumber(total)
  -- Shopping's buy view shows a higher quote to the player (Auctionator-style
  -- "price has increased" warning); every other path rejects any increase.
  if not self:Finite(unit,1,1e12) or not self:Finite(total,1,x.shop and 1e14 or x.live.cost) then
    self:InvalidateQuote('Price/quantity changed or invalid quote; revalidate'); return
  end
  local increased=total>x.live.cost
  x.live.cost=total; x.live.economics=self:Economics(x.market,total,x.live.quantity,x.opportunity.kind)
  if not self:ThrottleReady() then return end
  local pass,why=self:CheckRisk(x.market,x.live.economics)
  if not pass then self:InvalidateQuote(table.concat(why,'; ')); return end
  x.state='quoted'; x.quotedAt=GetTime(); x.message='Quote '..self:Money(total)..'; click CONFIRM QUOTE within '..(x.quoteWindow or 5)..' seconds'; self:RefreshUI()
  if x.shop and self.ShopBuyQuoted then self:ShopBuyQuoted(x,unit,total,increased) end
end)
M:RegisterHandler('COMMODITY_PRICE_UNAVAILABLE',function(self)
  local x=self.execution; if x.state=='quoting' or x.state=='quoted' then self:InvalidateQuote('Commodity price unavailable') end
end)
M:RegisterHandler('COMMODITY_PURCHASE_SUCCEEDED',function(self)
  local x=self.execution
  if x.order and x.commodity and (x.state=='pending' or x.state=='unknown') then
    self:ResolvePurchase(x.order,'confirmed','Observed COMMODITY_PURCHASE_SUCCEEDED'); x.state='complete'; x.message='Purchase confirmed'; self:RefreshUI()
  end
end)
M:RegisterHandler('COMMODITY_PURCHASE_FAILED',function(self)
  local x=self.execution
  if x.order and x.commodity and (x.state=='pending' or x.state=='unknown') then
    self:ResolvePurchase(x.order,'failed','Observed COMMODITY_PURCHASE_FAILED'); x.state='failed'; x.message='Purchase failed'; self:RefreshUI()
  elseif x.state=='quoting' or x.state=='quoted' then self:InvalidateQuote('Commodity request failed') end
end)
M:RegisterHandler('AUCTION_HOUSE_PURCHASE_COMPLETED',function(self,_,id)
  for _,p in pairs(self.db.pending) do
    if not p.commodity and p.auctionID==id and p.character==self.characterID then
      self:ResolvePurchase(p,'confirmed','Observed purchase completed for matching auction ID')
      if self.execution.order==p then self.execution.state='complete'; self.execution.message='Purchase confirmed' end
      break
    end
  end
end)
-- "You won an auction for X" (system chat) settles an item purchase whose
-- result event never arrived, e.g. the AH closed right after Buy Now.
function M:AuctionWonName(msg)
  if type(msg)~='string' then return nil end
  local template=ERR_AUCTION_WON_S or 'You won an auction for %s'
  local prefix,suffix=template:match('^(.-)%%s(.*)$'); if not prefix then return nil end
  prefix=prefix:gsub('(%W)','%%%1'); suffix=suffix:gsub('(%W)','%%%1')
  local name=msg:match('^'..prefix..'(.-)'..suffix..'$')
  if name and name:find('|h') then name=name:match('%[(.-)%]') or name end
  return name~='' and name or nil
end
function M:ResolveWonAuction(msg)
  local name=self:AuctionWonName(msg); if not name then return false end
  local want=name:lower();local best
  for _,p in pairs(self.db.pending) do
    local n=type(p.name)=='string' and p.name:lower() or ''
    if not p.commodity and p.character==self.characterID and n~=''
      and (n==want or want:sub(1,#n)==n or n:sub(1,#want)==want)
      and (not best or (p.id or 0)<(best.id or 0)) then best=p end
  end
  if not best then
    -- Bought outside Market (normal AH or another addon): record it from the bid sent.
    if self.RecordOutsideBuy then return self:RecordOutsideBuy(name) end
    return false
  end
  self:ResolvePurchase(best,'confirmed','Observed "auction won" system message')
  local x=self.execution
  if x and x.order==best then x.state='complete'; x.message='Purchase confirmed' end
  self:RefreshUI();return true
end
M:RegisterHandler('CHAT_MSG_SYSTEM',function(self,_,msg)
  local name=self:AuctionWonName(msg)
  if name and self.RecentAHNotice and self.RecentAHNotice(self,'won',name,'chat') then return end
  self:ResolveWonAuction(msg)
end)
function M:OldestUnresolvedPurchase()
  local best
  for _,p in pairs(self.db.pending) do
    if p.character==self.characterID and (not best or (p.id or 0)<(best.id or 0)) then best=p end
  end
  return best
end
-- "I got it" / "Didn't get it" in Shopping's buy view (same as the Ledger buttons).
function M:ShopSettleUnknown(got)
  local p=self:OldestUnresolvedPurchase();if not p then return false end
  self:ReviewPending(p,got)
  local x=self.execution;if x and x.order==p then x.state='idle';x.message=nil end
  self:Print((got and 'Marked bought: ' or 'Marked not bought: ')..tostring(p.name or 'item'))
  if self.ShopBuyRefresh and self.shopBuy and self.ahOpen then self:ShopBuyRefresh() end
  self:RefreshUI();return true
end
M:RegisterHandler('AUCTION_HOUSE_CLOSED',function(self)
  local x=self.execution
  if x.state=='pending' then x.order.status='unknown'; x.state='unknown'; x.message='AH closed before the result. If chat says you won the auction, this clears itself.'
  elseif x.state=='quoting' or x.state=='quoted' then self:InvalidateQuote('AH closed; quote discarded')
  elseif x.state~='complete' and x.state~='unknown' then x.state='stale'; x.message='AH closed; revalidate after reopening' end
  self:RefreshUI()
end)

M:RegisterHandler('AUCTION_HOUSE_SHOW_ERROR',function(self,_,code)
  self:Log('AH ERROR',tostring(code))
  local x=self.execution
  if x.state=='quoting' or x.state=='quoted' then self:InvalidateQuote('AH error: '..tostring(code))
  elseif x.state=='pending' then
    x.order.status='unknown'; x.order.evidence='AH error; transaction outcome uncertain'
    x.state='unknown'; x.message='AH error; check mailbox and reconcile outcome'
  end
  local r=self.queue.active; if r then self:FinishRequest(r,false,'AH error '..tostring(code)) end
  self:RefreshUI()
end)
