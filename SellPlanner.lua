local _,M=...
-- Advisory-only selling plans. No posting/cancel API is invoked by this module.
local STRATEGIES={'competitive','quick','median','margin'}
function M:GetSellStrategies() return STRATEGIES end
function M:SetSellStrategy(strategy)
  if self.persistenceBlocked then return false,'Newer database schema; changes disabled' end
  local found=false
  for _,s in ipairs(STRATEGIES) do if s==strategy then found=true; break end end
  if not found then return false,'Unknown selling strategy' end
  self.db.settings.sellStrategy=strategy
  self:RefreshInventory(); self:RefreshUI()
  return true
end
function M:SetSellFloor(key,copper)
  if self.persistenceBlocked then return false,'Newer database schema; changes disabled' end
  if not self.db.market[key] then return false,'Market variant unavailable' end
  if copper~=nil and (not self:Finite(copper,1,1e12) or copper%1~=0) then
    return false,'Enter a positive price in copper'
  end
  local floors=self.db.sellFloors
  local count=0
  for _ in pairs(floors) do count=count+1 end
  if floors[key]==nil and copper~=nil and count>=300 then return false,'300 per-item floors maximum' end
  floors[key]=copper
  self:RefreshInventory(); self:RefreshUI()
  return true
end
function M:BuildSellPlan(key,quantity)
  local m=key and self.db.market[key]
  local p={marketKey=key,quantity=quantity,price=nil,status='NO DATA',
    reason='No exact-variant market history; review the native Auction House.',
    basisKnown=false,depositEstimated=true}
  if not m or type(m.latest)~='table' then return p end
  p.itemID=m.itemID;p.name=m.name
  p.fair=m.fairValue
  p.floor=m.latest.floor
  p.confidence=m.confidence or 'Unknown'
  if not self:Finite(quantity,1,1e6) or quantity%1~=0 then
    p.status='INVALID'; p.reason='Invalid bag stack quantity'; return p
  end
  if m.analysisIncomplete or m.cacheUntrusted or not self:MarketFresh(m)
    or not self:Finite(m.fairValue,1,1e12) then
    p.status='STALE';p.reason='Untrusted, incomplete or outdated market valuation. Do not auto-price.'
    return p
  end
  local fair=m.fairValue
  local depth=m.latest.meaningfulFloor or m.latest.q10 or fair
  if not self:Finite(depth,1,1e12) then depth=fair end
  local settings=self.db.settings
  local strategy=settings.sellStrategy
  if strategy~='quick' and strategy~='median' and strategy~='margin' then strategy='competitive' end
  local price
  if strategy=='quick' then price=math.min(fair*0.90,depth*0.98)
  elseif strategy=='median' then price=fair
  elseif strategy=='margin' then price=math.max(fair*1.10,depth)
  else price=math.min(fair,depth)-1 end
  price=math.max(1,math.floor(price+0.5))
  p.strategy=strategy
  local own
  for _,r in ipairs(self.ownedRows or {}) do
    if r.marketKey==key and self:Finite(r.unit,1,1e12) then
      own=not own and r.unit or math.min(own,r.unit)
    end
  end
  if own then price=math.max(price,math.ceil(own)) end
  p.own=own
  local custom=self.db.sellFloors and self.db.sellFloors[key]
  if self:Finite(custom,1,1e12) then
    p.customFloor=custom;price=math.max(price,custom)
  end
  local lot=self.db.inventory and self.db.inventory[self:InventoryKey(key)]
  local basis
  if type(lot)=='table' and lot.character==self.characterID and
    self:Finite(lot.quantity,0.00001,1e9) and self:Finite(lot.cost,0,1e14) then
    basis=lot.cost/lot.quantity
    if self:Finite(basis,0,1e12) then
      p.basisUnit=basis
      p.basisKnown=lot.quantity>=quantity
      p.coveredQuantity=math.min(lot.quantity,quantity)
    end
  end
  local cut=settings.ahCut or 0.05
  if not self:Finite(cut,0,0.30) then cut=0.05 end
  local deposit=settings.depositReserve or 0
  if not self:Finite(deposit,0,1e9) then deposit=0 end
  local margin=settings.sellMinMargin or 0
  if not self:Finite(margin,0,2) then margin=0 end
  if basis then
    p.minimumBreakEven=math.ceil((basis*(1+margin)+deposit)/(1-cut))
    price=math.max(price,p.minimumBreakEven)
  end
  if not self:Finite(price,1,1e12) then
    p.status='INVALID';p.reason='Calculated price exceeds supported bounds';return p
  end
  p.price=price;p.depositAllowance=math.ceil(deposit*quantity)
  p.gross=price*quantity
  p.estimatedCut=math.ceil(p.gross*cut)
  p.estimatedNet=p.gross-p.estimatedCut-p.depositAllowance
  p.profit=p.basisKnown and p.estimatedNet-basis*quantity or nil
  p.roi=p.profit and basis*quantity>0 and p.profit/(basis*quantity) or nil
  local risks={}
  if self:Finite(m.latest.floor,1,1e12) and m.latest.floor<depth*0.75 then
    risks[#risks+1]='Very low listing may be isolated price bait'
  end
  if (m.observations or 0)<3 then risks[#risks+1]='Less than three independent scans' end
  if (m.confidenceScore or 0)<(settings.minConfidence or 42) then risks[#risks+1]='Low model confidence' end
  if (m.volatility or 0)>(settings.riskTolerance or 0.35) then risks[#risks+1]='High price volatility' end
  if not p.basisKnown then
    risks[#risks+1]=basis and 'Only part of this stack has known acquisition cost' or 'Acquisition cost unknown (possibly gathered/mailed)'
  end
  if own then risks[#risks+1]='Your own existing auction price is protected against self-undercutting' end
  if price>fair*1.35 then
    p.status='HOLD'
    risks[#risks+1]='Floor/breakeven requires a price far above fair value'
  elseif #risks>0 then p.status='REVIEW'
  else p.status='ESTIMATE' end
  p.reason=table.concat(risks,'; ')
  if p.reason=='' then p.reason='Snapshot-based suggestion; verify live prices and native AH deposit before posting' end
  return p
end

-- Repricing is always a review signal. No cancellation or native post is made.
function M:AssessOwnedRepost(row,competitor,cancelCost)
  local out={action='HOLD',reason='Insufficient information to justify cancel/repost'}
  if type(row)~='table' or not self:Finite(row.unit,1,1e12)
    or not self:Finite(row.quantity,1,1e6) then return out end
  if not self:Finite(competitor,1,1e12) then
    out.reason='No eligible competing supply in complete live search; keep the listing'
    return out
  end
  if competitor>=row.unit then
    out.reason='Your listing remains competitive; hold it rather than pay another deposit'
    return out
  end
  local market=self.db.market[row.marketKey]
  if not market or market.analysisIncomplete or not self:MarketFresh(market) then
    out.reason='Market model missing/stale; cannot justify cancellation'
    return out
  end
  local anchor=market.latest and (market.latest.meaningfulFloor or market.latest.q10)
  if self:Finite(anchor,1,1e12) and competitor<anchor*0.75 then
    out.reason='Undercut appears far below meaningful market depth; possible bait, hold'
    return out
  end
  local reducedUnit=math.max(1,math.floor(competitor-1))
  local revenueDecrease=math.ceil((row.unit-reducedUnit)*row.quantity)
  out.proposedUnit=reducedUnit;out.revenueDecrease=revenueDecrease
  if not self:Finite(cancelCost,0,1e12) or not self:Finite(row.deposit,0,1e12) then
    out.reason='Undercut observed, but actual cancellation cost/deposit is unknown; do not cancel on estimates'
    return out
  end
  local totalFriction=cancelCost+row.deposit
  local gap=(row.unit-competitor)/row.unit
  out.action=gap>=0.15 and 'REVIEW' or 'HOLD'
  out.reason=string.format('Live competitor %.1f%% below your unit price. Repricing near %s reduces gross by %s; known cancellation fee %s plus listed deposit at risk %s. %s',
    gap*100,self:Money(reducedUnit),self:Money(revenueDecrease),self:Money(cancelCost),self:Money(row.deposit),
    out.action=='REVIEW' and 'Review remaining time and demand before deciding in native AH.' or 'Price gap is modest; holding avoids needless churn.')
  return out
end
