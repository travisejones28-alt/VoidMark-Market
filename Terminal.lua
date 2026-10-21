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
