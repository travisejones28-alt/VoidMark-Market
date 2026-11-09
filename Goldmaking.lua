local _,M=...
-- Optional verified disenchant distributions are session-only. No speculative seed data.
M.disenchantModels={}
function M:RegisterDisenchantModel(itemID,model)
  if not self:Finite(itemID,1,1e9) or type(model)~='table' or model.verified~=true
    or type(model.source)~='string' or #model.source<3 or #model.source>200
    or type(model.outcomes)~='table' or #model.outcomes==0 or #model.outcomes>20 then return false end
  local sum,out=0,{}
  for _,o in ipairs(model.outcomes) do
    if not self:Finite(o.probability,0.000001,1) or type(o.items)~='table' or #o.items>10 then return false end
    sum=sum+o.probability;local items={}
    for _,v in ipairs(o.items) do
      if not self:Finite(v.itemID,1,1e9) or not self:Finite(v.quantity,1,100) or v.quantity%1~=0 then return false end
      items[#items+1]={itemID=v.itemID,quantity=v.quantity}
    end
    out[#out+1]={probability=o.probability,items=items}
  end
  if math.abs(sum-1)>0.000001 then return false end
  local count=0;for _ in pairs(self.disenchantModels) do count=count+1 end
  if not self.disenchantModels[itemID] and count>=100 then return false end
  self.disenchantModels[itemID]={source=model.source,outcomes=out};return true
end
function M:EvaluateDisenchant(itemID)
  local model=self.disenchantModels[itemID];local m=self:BaseMarket(itemID)
  if not model or not m then return nil end
  local q=self:QuoteAcquisition(itemID,1,{auctionOnly=true});if not q or q.purchasedQuantity~=1 then return nil end
  local revenue,confidence=0,100
  for _,o in ipairs(model.outcomes) do for _,v in ipairs(o.items) do
    local p=self:GetPriceInfo(v.itemID);if not p.resaleReady then return nil end
    confidence=math.min(confidence,p.confidence)
    local factor=math.min(0.9,math.max(0.1,p.liquidity/100))
    revenue=revenue+o.probability*v.quantity*(p.resalePrice*(1-self.db.settings.ahCut)*factor-self.db.settings.depositReserve)
  end end
  local e={cost=q.totalCost,quantity=1,net=math.floor(revenue)-q.totalCost,kind='disenchant'};e.roi=e.net/e.cost
  local pass,blocks=self:CheckRisk(m,e)
  return {name=m.name,itemID=itemID,marketKey=m.marketKey,kind='disenchant',economics=e,pass=pass,blocks=blocks,
    confidence=confidence,score=math.min(100,math.max(0,e.roi)*20+confidence*0.4),source=model.source}
end
function M:RebuildGoldmaking()
  if not self.db then return end
  self.goldmakingRows={}
  local worker=coroutine.create(function()
  local out={};local materials={}
  for _,r in pairs(self.db.recipes or {}) do for _,v in ipairs(r.reagents or {}) do materials[v.itemID]=true end;coroutine.yield() end
  for _,o in ipairs(self.db.opportunities or {}) do
    local m=self.db.market[o.marketKey]
    -- Base depth cannot be substituted for a suffix-specific market.
    if m and m.marketKey==m.itemID and (o.kind=='vendor' or self:CanEstimateResale(m)) then
      local depth=self:GetProfitableDepth(m,o.kind)
      if depth then out[#out+1]={name=o.name,itemID=o.itemID,marketKey=o.marketKey,
        kind=o.kind=='vendor' and 'Vendor arbitrage' or materials[o.itemID] and 'Material resale' or 'Auction flip',
        cost=depth.economics.cost,net=depth.economics.net,roi=depth.economics.roi,
        quantity=depth.economics.quantity,confidence=o.confidenceScore,score=o.score,pass=true,
        snapshotAt=m.lastSeen,economics=depth.economics,
        reason='Snapshot whole-stack depth. Use SNIPER for live purchase validation.'} end
    end
    coroutine.yield()
  end
  for _,r in ipairs(self.craftRows or {}) do if r.pass then
    out[#out+1]={name=r.name,itemID=r.itemID,kind='Crafting',cost=r.cost,net=r.net,roi=r.roi,quantity=r.quantity,
      confidence=r.confidence,score=r.score,pass=true,recipe=r.recipe,crafts=r.crafts,craftRow=r,
      reason='Sale scenario haircut included; inspect Crafting Intelligence.'}
  end;coroutine.yield() end
  for id in pairs(self.disenchantModels) do local r=self:EvaluateDisenchant(id);if r and r.pass then
    out[#out+1]={name=r.name,itemID=id,kind='Disenchant',cost=r.economics.cost,net=r.economics.net,roi=r.economics.roi,
      quantity=1,confidence=r.confidence,score=r.score,pass=true,disenchant=true,reason='Distribution: '..r.source..'; character eligibility must be checked in game.'}
  end;coroutine.yield() end
  table.sort(out,function(a,b) return a.score==b.score and a.itemID<b.itemID or a.score>b.score end)
  return out
  end)
  self:AddJob('goldmaking',function(start)
    -- Several worker steps per frame within the background budget (was one).
    repeat
      local ok,result=coroutine.resume(worker);if not ok then error(result) end
      if coroutine.status(worker)=='dead' then self.goldmakingRows=result;return true end
    until debugprofilestop()-start>=3
  end,function() self:RefreshUI() end)
end
function M:GetGoldmakingRows()
  local rows={}
  for _,r in ipairs(self.goldmakingRows or {}) do
    local valid
    if r.craftRow then valid=self:IsCraftCurrent(r.craftRow) and self:CheckRisk(self:BaseMarket(r.itemID),r.craftRow.economics)
    elseif r.disenchant then local e=self:EvaluateDisenchant(r.itemID);valid=e and e.pass
    else
      local m=self:BaseMarket(r.itemID);local q=self:QuoteAcquisition(r.itemID,r.quantity,{auctionOnly=true})
      valid=m and q and m.lastSeen==r.snapshotAt and q.totalCost==r.cost and self:CheckRisk(m,r.economics)
    end
    if valid then rows[#rows+1]=r end
  end
  return rows
end
