local _,M=...
-- Snapshot quotes only. These functions never scan, buy, post, or authorize trades.
function M:StoreAcquisitionDepth(m,g,at)
  local lots={}
  for _,v in ipairs(g.acquisitionLots or {}) do
    lots[#lots+1]={quantity=v.quantity,cost=v.cost,count=v.count}
  end
  table.sort(lots,function(a,b) return a.cost/a.quantity<b.cost/b.quantity end)
  m.depth={at=at,lots=lots,incomplete=g.depthIncomplete or g.acquisitionLots==nil}
end
function M:BaseMarket(itemID)
  -- Never price a recipe's base output using a random suffix or pet variant.
  return self.db and self.db.market[tonumber(itemID)]
end
function M:GetPriceInfo(itemID)
  local m=self:BaseMarket(itemID)
  local p={itemID=itemID,availableQuantity=0,confidence=0,status='unavailable',apiVersion=1}
  if type(m)~='table' then return p end
  p.timestamp=m.lastSeen;p.confidence=m.confidenceScore or 0
  p.historicalPrice=m.historicalFair;p.liquidity=m.activityScore or 0
  local valid=self:MarketFresh(m) and not m.cacheUntrusted and not m.analysisIncomplete
    and m.lastSeen>=(self.db.lastDepthSnapshotAt or 0)
  p.status=valid and 'current' or 'stale';p.source=valid and 'auction snapshot' or 'historical estimate'
  if valid then
    p.price=m.latest and m.latest.meaningfulFloor
    p.resaleReady=self:CanEstimateResale(m)
    p.resalePrice=p.resaleReady and math.floor(math.min(m.fairValue,m.latest.meaningfulFloor or m.fairValue)) or nil
    if type(m.depth)=='table' and type(m.depth.lots)=='table' and not m.depth.incomplete and m.depth.at==m.lastSeen then
      for _,l in ipairs(m.depth.lots) do
        if type(l)=='table' and self:Finite(l.quantity,1,100000) and self:Finite(l.count,1,1e7) then p.availableQuantity=p.availableQuantity+l.quantity*l.count end
      end
    end
  end
  return p
end
function M:QuoteAcquisition(itemID,quantity,options)
  if not self.db then return nil,'Market database not initialized' end
  options=options or {}
  if not self:Finite(itemID,1,1e9) or itemID%1~=0 or not self:Finite(quantity,1,100000) or quantity%1~=0 then return nil,'Invalid item or quantity' end
  local m=self:BaseMarket(itemID); local d=m and m.depth
  local quote,reason
  if not m or not self:MarketFresh(m) or m.cacheUntrusted or m.analysisIncomplete
    or m.lastSeen<(self.db.lastDepthSnapshotAt or 0) then reason='Missing or stale auction data'
  elseif type(d)~='table' or type(d.lots)~='table' or #d.lots>512 or d.incomplete or d.at~=m.lastSeen then reason='Complete acquisition depth unavailable; run a fresh scan'
  else
    local cost,bought,available,tiers=0,0,0,{}
    local anchor=m.latest and m.latest.median
    local ceiling=self:Finite(anchor,1,1e12) and anchor*4 or 0
    for _,l in ipairs(d.lots or {}) do
      if type(l)=='table' and self:Finite(l.quantity,1,100000) and l.quantity%1==0 and self:Finite(l.cost,1,1e12)
        and self:Finite(l.count,1,1e7) and l.count%1==0 and l.cost/l.quantity<=ceiling then
        available=available+l.quantity*l.count
        if bought<quantity then
          local count=math.min(l.count,math.ceil((quantity-bought)/l.quantity))
          cost=cost+l.cost*count;bought=bought+l.quantity*count
          tiers[#tiers+1]={quantity=l.quantity*count,cost=l.cost*count,unitPrice=l.cost/l.quantity,stacks=count}
        end
      end
    end
    if bought>=quantity then
      quote={itemID=itemID,quantity=quantity,purchasedQuantity=bought,surplus=bought-quantity,totalCost=cost,
        unitCost=cost/quantity,marginalPrice=tiers[#tiers].unitPrice,availableQuantity=available,
        timestamp=d.at,confidence=m.confidenceScore or 0,tiers=tiers,source='auction snapshot',requiresLiveCheck=true}
    else reason='Insufficient non-outlier auction stock' end
  end
  local v=self.db.vendorMaterials and self.db.vendorMaterials[itemID]
  -- Only observed, unlimited, money-only vendor offers; no buyback/sell-value inference.
  if not options.auctionOnly and type(v)=='table' and v.character==self.characterID and self:Finite(v.price,1,1e12)
    and self:Finite(v.bundle,1,10000) and v.bundle%1==0 and self:Finite(v.at,time()-86400,time()) then
    local count=math.ceil(quantity/v.bundle)*v.bundle;local cost=count*v.price
    if not quote or cost<quote.totalCost then
      quote={itemID=itemID,quantity=quantity,purchasedQuantity=count,surplus=count-quantity,totalCost=cost,
        unitCost=cost/quantity,marginalPrice=v.price,availableQuantity=count,timestamp=v.at,confidence=100,
        source='observed vendor',requiresLiveCheck=true,tiers={{quantity=count,cost=cost,unitPrice=v.price}}}
    end
  end
  return quote,quote and nil or reason
end
function M:GetProfitableDepth(m,kind)
  local best
  for n=1,math.min(100,self.db.settings.maxQuantity) do
    local q=self:QuoteAcquisition(m.itemID,n,{auctionOnly=true})
    if not q then break end
    local e=self:Economics(m,q.totalCost,q.purchasedQuantity,kind)
    local pass=self:CheckRisk(m,e)
    if pass and (not best or e.net>best.economics.net) then best={quote=q,economics=e} end
  end
  return best
end
-- Versioned, optional local contract. Callers get new tables, never database aliases.
M.PricingAPI={version=1}
function M.PricingAPI.GetObservedAsk(itemID,suffix,level,pet)
 local o=M:PriceObservation(M:Key(itemID,suffix,level,pet));if not o then return nil end
 return {unit=o.floor,at=o.at,source=o.source,stale=o.unverified or time()-o.at>M.db.settings.maxDataAge}
end
function M.PricingAPI.GetPrice(itemID) return M:GetPriceInfo(itemID) end
function M.PricingAPI.GetAcquisitionCost(itemID,quantity) return M:QuoteAcquisition(itemID,quantity) end
function M.PricingAPI.GetFarmingComparison(itemID,unitsPerHour)
  if not M:Finite(unitsPerHour,0.01,100000) then return nil,'Measured yield per hour required' end
  local p=M:GetPriceInfo(itemID)
  if not p.resaleReady then return nil,'Reliable resale estimate unavailable' end
  return {itemID=itemID,grossPerHour=p.resalePrice*unitsPerHour,
    netPerHour=(p.resalePrice*(1-M.db.settings.ahCut)-M.db.settings.depositReserve)*unitsPerHour,
    confidence=p.confidence,timestamp=p.timestamp,assumption='Provided yield; sales and travel time not guaranteed'}
end
