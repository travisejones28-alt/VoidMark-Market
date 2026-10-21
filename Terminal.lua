local _,M=...
-- Local banker analytics. Auction snapshots are observations, not executed trades.
-- All state is scoped to the current realm/faction economy by Database.lua.
function M:RecordBankerScan(summary)
  if not self.db or not self.db.banker then return end
  local banker=self.db.banker
  local prior=banker.latest or {}
  local found,news={},{}
  local top=self.db.opportunities or {}
  for i=1,math.min(#top,200) do
    local o=top[i]
    if o and o.marketKey and o.pass then
      local key=tostring(o.marketKey)
      found[key]={score=o.score,ask=o.floor}
      if not (prior.items and prior.items[key]) then
        news[#news+1]={key=key,score=o.score,name=o.name or ('Item '..tostring(o.itemID))}
      end
    end
  end
  banker.latest={at=time(),scanID=summary.marketScanID or 0,items=found}
  banker.new=news -- capped by the 200-opportunity ranking
  banker.previousAt=prior.at
  self:RefreshUI()
end

function M:SetWatch(marketKey,target)
  if self.persistenceBlocked then return false,'Database read-only' end
  local market=self.db.market[marketKey]
  if not market or not market.marketKey then return false,'Market not indexed yet' end
  if target~=nil and (not self:Finite(target,1,1e12) or target%1~=0) then return false,'Target must be positive copper' end
  local count=0
  for _ in pairs(self.db.watchlist) do count=count+1 end
  if not self.db.watchlist[marketKey] and count>=200 then return false,'200 watch entries maximum' end
  self.db.watchlist[marketKey]={at=time(),target=target,name=market.name or ('Item '..tostring(market.itemID))}
  self:RefreshUI()
  return true
end
function M:RemoveWatch(marketKey)
  if self.persistenceBlocked then return false end
  self.db.watchlist[marketKey]=nil; self:RefreshUI(); return true
end
function M:GetWatchRows()
  local out={}
  for key,entry in pairs(self.db.watchlist or {}) do
    if type(entry)=='table' then
      local m=self.db.market[key]
      local fresh=m and not m.analysisIncomplete and self:MarketFresh(m) or false
      local floor=m and m.latest and m.latest.floor or 0
      local status=not m and 'MISSING' or not fresh and 'STALE'
        or (entry.target and floor>0 and floor<=entry.target) and 'TARGET' or 'WATCH'
      out[#out+1]={marketKey=key,itemID=m and m.itemID,name=m and m.name or entry.name or tostring(key),
        floor=floor,fair=m and m.fairValue or 0,target=entry.target,confidence=m and m.confidence or 'Unknown',
        status=status,watchedAt=entry.at or 0,fresh=fresh}
    end
  end
  table.sort(out,function(a,b)
    if (a.status=='TARGET')~=(b.status=='TARGET') then return a.status=='TARGET' end
    return tostring(a.name)<tostring(b.name)
  end)
  return out
end
function M:GetPortfolioRows()
  local rows={}
  local totals={cost=0,marketValue=0,estimatedNet=0,unrealized=0,unvaluedCost=0,positions=0,quantity=0}
  local cut=self.db.settings.ahCut or 0.05
  local allowance=self.db.settings.depositReserve or 0
  for _,lot in pairs(self.db.inventory or {}) do
    if type(lot)=='table' and lot.character==self.characterID then
      local qty,cost=tonumber(lot.quantity) or 0,tonumber(lot.cost) or 0
      if self:Finite(qty,0,1e9) and self:Finite(cost,0,1e14) and qty>0 then
        local m=self.db.market[lot.marketKey]
        local fresh=m and not m.analysisIncomplete and not m.cacheUntrusted and
          self:MarketFresh(m) and self:Finite(m.fairValue,1,1e12)
        local gross=fresh and math.floor(qty*m.fairValue) or nil
        local net=gross and math.max(0,gross-math.ceil(gross*cut)-math.ceil(qty*allowance)) or nil
        local unrealized=net and net-cost or nil
        totals.positions=totals.positions+1; totals.quantity=totals.quantity+qty
        totals.cost=totals.cost+cost
        if net then
          totals.marketValue=totals.marketValue+gross
          totals.estimatedNet=totals.estimatedNet+net
          totals.unrealized=totals.unrealized+unrealized
        else totals.unvaluedCost=totals.unvaluedCost+cost end
        rows[#rows+1]={marketKey=lot.marketKey,name=m and m.name or ('Item '..tostring(lot.marketKey)),
          quantity=qty,cost=cost,basis=cost/qty,marketValue=gross,estimatedNet=net,
          unrealized=unrealized,roi=cost>0 and unrealized and unrealized/cost or nil,
          status=fresh and 'ESTIMATE' or 'UNPRICED',firstSeen=lot.firstSeen}
      end
    end
  end
  table.sort(rows,function(a,b)return a.cost>b.cost end)
  return rows,totals
end
function M:GetBankerSummary()
  local ledger=self:LedgerTotals()
  local rows,portfolio=self:GetPortfolioRows()
  local reserve=self.db.settings.minGoldReserve or 0
  local money=GetMoney and GetMoney() or 0
  local available=math.max(0,money-ledger.reserved-reserve)
  return {gold=money,reserve=reserve,available=available,pending=ledger.reserved,
    realized=ledger.realized,revenue=ledger.revenue,fees=ledger.fees,
    portfolio=portfolio,portfolioRows=rows,scanner=self.db.banker,
    latestScan=self.db.latestScan}
end

-- Nonblocking search across the existing indexed snapshot; capped to avoid 20k-row UI allocations.
function M:BuildBrowseRows(query)
  self:CancelJob('browse')
  local token=(self.browseToken or 0)+1;self.browseToken=token
  local keys=self.marketIndex or {};local i=1;local out={}
  local needle=tostring(query or ''):lower()
  self.browseRows={}
  self:AddJob('browse',function(start)
    for j=1,80 do
      if i>#keys or #out>=300 then return true end
      local m=self.db.market[keys[i]];i=i+1
      if m and type(m.name)=='string' and m.name:lower():find(needle,1,true) then
        local fresh=m.latest and self:MarketFresh(m) and not m.analysisIncomplete
        local week,month=self:MarketWindow(m,7),self:MarketWindow(m,30)
        out[#out+1]={marketKey=m.marketKey,itemID=m.itemID,name=m.name,floor=m.latest and m.latest.floor or 0,
          fair=m.fairValue or 0,quantity=m.latest and m.latest.quantity or 0,
          median7=week and week.median,median30=month and month.median,
          confidence=m.confidence or 'Unknown',status=fresh and 'CACHED' or 'STALE'}
      end
      if debugprofilestop()-start>=4 then return false end
    end
  end,function()
    if token~=self.browseToken then return end
    -- Imported observations are labeled separately and never become local market history.
    for key,s in pairs(self.db.sharedPrices or {}) do
      if #out>=300 then break end
      if type(s)=='table' and not self.db.market[key] and
        (needle=='' or tostring(s.id):find(needle,1,true)) then
        local fresh=self:Finite(s.at,time()-(self.db.settings.maxDataAge or 7200),time()+300)
        out[#out+1]={marketKey=key,itemID=s.id,name='Item '..tostring(s.id)..' (manual share)',
          floor=0,fair=s.fair,quantity=s.quantity or 0,confidence=tostring(s.confidence)..' (shared)',
          status=fresh and 'SHARED*' or 'SHARED OLD'}
      end
    end
    table.sort(out,function(x,y)return tostring(x.name)<tostring(y.name) end)
    self.browseRows=out;self:RefreshUI()
  end)
end

-- Each full scan is one sample; a 7/30-day median treats scans equally, not
-- thousands of correlated listings as thousands of independent observations.
function M:MarketWindow(m,days)
  if type(m)~='table' or type(m.history)~='table' then return nil end
  local values,now={},time()
  for _,h in ipairs(m.history) do
    if type(h)=='table' and self:Finite(h.at,now-days*86400,now+300)
      and self:Finite(h.median,1,1e12) then
      values[#values+1]=h.median
    end
  end
  if #values==0 then return nil end
  table.sort(values)
  local n=#values
  local med=n%2==1 and values[(n+1)/2] or (values[n/2]+values[n/2+1])/2
  return {median=math.floor(med+0.5),samples=n,low=values[1],high=values[n]}
end
function M:GetSniperRows(filter,sort)
  local out={}
  local q=tostring(filter or ''):lower()
  for _,o in ipairs(self.db.opportunities or {}) do
    if type(o)=='table' and type(o.name)=='string' and o.name:lower():find(q,1,true) then
      out[#out+1]=o
    end
  end
  local function metric(o)
    if sort=='profit' then return o.economics and o.economics.net or 0 end
    if sort=='roi' then return o.economics and o.economics.roi or 0 end
    if sort=='confidence' then return o.confidenceScore or 0 end
    if sort=='liquidity' then return o.activityScore or 0 end
    if sort=='discount' then return o.economics and o.economics.discount or 0 end
    if sort=='ask' then return o.floor or 0 end
    return o.score or 0
  end
  table.sort(out,function(a,b)
    if sort=='name' then
      if a.name~=b.name then return a.name<b.name end
    else
      local av,bv=metric(a),metric(b)
      if av~=bv then return av>bv end
    end
    return tostring(a.marketKey)<tostring(b.marketKey)
  end)
  return out
end

-- Player-reviewed shortlist. Queue entries NEVER imply a valid quote, a reserved
-- transaction, or a completed purchase; every row must be revalidated live.
function M:QueuePurchaseReview(opportunity)
  if self.persistenceBlocked then return false,'Newer database schema; queue disabled' end
  if type(opportunity)~='table' or not opportunity.marketKey then return false,'Select an opportunity first' end
  local m=self.db.market[opportunity.marketKey]
  if not m then return false,'Market unavailable' end
  local list=self.db.reviewQueue
  local count=0;for _ in pairs(list) do count=count+1 end
  if not list[opportunity.marketKey] and count>=100 then return false,'Review queue limited to 100 items' end
  list[opportunity.marketKey]={marketKey=opportunity.marketKey,itemID=m.itemID,
    name=m.name,queuedAt=time(),snapshotAsk=opportunity.floor,
    snapshotROI=opportunity.economics and opportunity.economics.roi or 0}
  self:RefreshUI()
  return true
end
function M:RemovePurchaseReview(key)
  if self.persistenceBlocked or key==nil then return false end
  self.db.reviewQueue[key]=nil
  self:RefreshUI()
  return true
end
function M:GetPurchaseReviewRows()
  local out,opps={},{}
  for _,o in ipairs(self.db.opportunities or {}) do
    if type(o)=='table' and o.marketKey then opps[tostring(o.marketKey)]=o end
  end
  for key,item in pairs(self.db.reviewQueue or {}) do
    if type(item)=='table' and item.marketKey then
      local m=self.db.market[item.marketKey]
      local o=opps[tostring(item.marketKey)]
      local fresh=m and not m.analysisIncomplete and self:MarketFresh(m)
      local valid=fresh and o and o.pass
      out[#out+1]={marketKey=item.marketKey,itemID=item.itemID,
        name=m and m.name or item.name or ('Item '..tostring(item.itemID)),
        snapshotAsk=item.snapshotAsk or 0,ask=o and o.floor or 0,
        roi=o and o.economics and o.economics.roi or item.snapshotROI or 0,
        fair=m and m.fairValue or 0,confidence=o and o.confidence or 'Unknown',
        status=valid and 'REVALIDATE' or 'RECHECK',opportunity=valid and o or nil,
        queuedAt=item.queuedAt or 0}
    end
  end
  table.sort(out,function(x,y)
    if x.queuedAt~=y.queuedAt then return x.queuedAt>y.queuedAt end
    return tostring(x.name)<tostring(y.name)
  end)
  return out
end
