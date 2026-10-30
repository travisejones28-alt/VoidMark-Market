local _,M=...
local function copy(t) local o={};for k,v in pairs(t) do o[k]=v end;return o end
local function clone(s) return {needs=copy(s.needs),pool=copy(s.pool),bagPool=copy(s.bagPool),used=copy(s.used),owned=s.owned,steps=copy(s.steps)} end
local function total(M,s)
  local cost,rows=0,{}
  for id,n in pairs(s.needs) do
    local q,why=M:QuoteAcquisition(id,n)
    if not q then return nil,why..' (item '..id..')' end
    cost=cost+q.totalCost;rows[id]=q
  end
  return cost,rows
end
-- Every branch shares a strict work budget. Whole-project totals account for
-- repeated reagents and depth; recipes never recurse indefinitely.
local function resolve(M,id,qty,s,path,depth,budget)
  budget.n=budget.n+1
  if budget.n>128 or depth>8 then return nil,'Crafting chain complexity limit' end
  s=clone(s)
  if s.pool[id]==nil then
    local count=0;if s.owned then count=M:OwnedMaterial(id) end
    if count==nil then return nil,'Bag inventory API unavailable' end
    s.pool[id]=count
    s.bagPool[id]=count
  end
  local owned=math.min(qty,s.pool[id]);s.pool[id]=s.pool[id]-owned
  local bagUsed=math.min(owned,s.bagPool[id] or 0);s.bagPool[id]=(s.bagPool[id] or 0)-bagUsed
  s.used[id]=(s.used[id] or 0)+bagUsed;qty=qty-owned
  if qty==0 then return s end
  local direct=clone(s);direct.needs[id]=(direct.needs[id] or 0)+qty
  local bestCost,err=total(M,direct);local best=bestCost and direct
  if not path[id] then
    local branch=copy(path);branch[id]=true
    for i,r in ipairs(M:RecipeCandidates(id)) do
      if i>3 then break end -- deterministic bounded alternative search
      local trial=clone(s);local crafts=math.ceil(qty/r.output);local fail
      for _,v in ipairs(r.reagents) do
        trial,fail=resolve(M,v.itemID,v.quantity*crafts,trial,branch,depth+1,budget)
        if not trial then break end
      end
      if trial then
        trial.pool[id]=(trial.pool[id] or 0)+crafts*r.output-qty
        trial.steps[#trial.steps+1]=r.name..' x'..crafts
        local cost=total(M,trial)
        if cost and (not bestCost or cost<bestCost) then best,bestCost=trial,cost end
      else err=fail or err end
    end
  end
  return best,err or 'No priced acquisition path'
end
function M:NewMaterialState(owned) return {needs={},pool={},bagPool={},used={},steps={},owned=owned} end
function M:ExpandCraft(r,crafts,state)
  local s=clone(state or self:NewMaterialState(false));local budget={n=0}
  for _,v in ipairs(r.reagents) do
    local why;s,why=resolve(self,v.itemID,v.quantity*crafts,s,{[r.itemID]=true},1,budget)
    if not s then return nil,why end
  end
  return s
end
function M:EvaluateCraft(r,crafts)
  local row={id=r.id,recipe=r,name=r.name,itemID=r.itemID,profession=r.profession,crafts=crafts,
    quantity=crafts*r.output,pass=false,status='UNPRICED',blocks={},worthCrafting=0}
  local economic,why=self:ExpandCraft(r,crafts)
  if not economic then row.reason=why;return row end
  row.cost,row.materials=total(self,economic);row.steps=economic.steps
  local cash,cashWhy=self:ExpandCraft(r,crafts,self:NewMaterialState(true))
  if cash then row.cashCost,row.shopping=total(self,cash);row.owned=cash.used else row.inventoryReason=cashWhy end
  local finished=self:QuoteAcquisition(r.itemID,row.quantity)
  row.buyFinished=finished and finished.totalCost;row.makeSaving=row.buyFinished and row.buyFinished-row.cost
  local p=self:GetPriceInfo(r.itemID);row.confidence=p.confidence
  row.snapshotAt=p.timestamp
  if not p.resaleReady then row.reason='Output needs fresh, reliable resale history';return row end
  local m=self:BaseMarket(r.itemID);local s=self.db.settings
  row.price=p.resalePrice;row.gross=row.price*row.quantity;row.fee=math.ceil(row.gross*s.ahCut)
  row.depositReserve=s.depositReserve*row.quantity
  -- Supply churn is not sales. This explicit scenario haircut is NOT a measured sale rate.
  row.saleFactor=math.max(0.1,math.min(0.9,(m.activityScore or 0)/100))
  row.expectedRevenue=math.floor((row.gross-row.fee)*row.saleFactor)-row.depositReserve
  row.netIfSold=row.gross-row.fee-row.depositReserve-row.cost
  row.net=row.expectedRevenue-row.cost;row.roi=row.cost>0 and row.net/row.cost or 0
  row.breakeven=math.ceil((row.cost+row.depositReserve)/(row.quantity*(1-s.ahCut)*row.saleFactor))
  row.economics={cost=row.cost,quantity=row.quantity,net=row.net,roi=row.roi,kind='crafting'}
  row.pass,row.blocks=self:CheckRisk(m,row.economics)
  local function block(message) row.pass=false;row.blocks[#row.blocks+1]=message end
  if not self:KnownRecipe(r) then block('Recipe not recorded as learned by this character') end
  if not cash then block(cashWhy) end
  for id,q in pairs(row.materials) do
    row.confidence=math.min(row.confidence,q.confidence)
    if q.source~='observed vendor' and q.confidence<s.minConfidence then block('Low reagent confidence: '..id) end
  end
  local supply=m.latest and m.latest.quantity or 0
  row.liquidityCap=math.max(1,math.floor(supply*0.10*row.saleFactor))
  if row.quantity>row.liquidityCap then block('Conservative output supply limit') end
  row.score=math.max(0,math.min(100,math.log(1+math.max(0,row.net)/100)*7+math.max(0,row.roi)*10+
    row.confidence*0.25+(m.activityScore or 0)*0.20-(m.volatility or 0)*30))
  row.status=row.pass and 'CANDIDATE' or 'BLOCKED';row.reason=table.concat(row.blocks,'; ')
  if row.pass then row.worthCrafting=crafts end
  return row
end
function M:RebuildCrafting()
  if not self.db or not self.db.recipes then return end
  self.craftRows={};self.goldmakingRows={}
  local recipes={};self.recipeByItem={}
  for _,r in pairs(self.db.recipes) do
    if type(r)=='table' and type(r.id)=='string' and type(r.reagents)=='table' then
      recipes[#recipes+1]=r
      if self:KnownRecipe(r) then
        self.recipeByItem[r.itemID]=self.recipeByItem[r.itemID] or {}
        table.insert(self.recipeByItem[r.itemID],r)
      end
    end
  end
  for _,rs in pairs(self.recipeByItem) do table.sort(rs,function(a,b) return a.id<b.id end) end
  table.sort(recipes,function(a,b) return a.id<b.id end)
  local i,n,rows,best=1,1,{},nil
  self.craftingBusy=true
  self:AddJob('crafting',function()
    local r=recipes[i];if not r then return true end
    local row=self:EvaluateCraft(r,n)
    if n==1 or (row.pass and (not best.pass or row.net>best.net)) then best=row end
    local max=math.min(50,math.floor(self.db.settings.maxQuantity/r.output))
    if n>=max or not row.pass then rows[#rows+1]=best;i=i+1;n=1;best=nil else n=n+1 end
    return false -- one bounded chain evaluation per frame
  end,function()
    self.craftRows=rows;self.craftingBusy=false;self.craftRevision=self.craftRevision+1
    self:BuildCraftShopping();self:RebuildGoldmaking();self:RefreshUI()
  end)
end
function M:GetCraftRows(filter,sort)
  local out={};filter=(filter or ''):lower()
  for _,r in ipairs(self.craftRows or {}) do
    if r.pass and not self:IsCraftCurrent(r) then
      r=copy(r);r.pass=false;r.status='STALE';r.worthCrafting=0;r.net=nil;r.roi=nil;r.score=0;r.reason='Prices changed or expired; recalculate'
    end
    if (r.name..' '..r.profession..' '..r.itemID..' '..r.status):lower():find(filter,1,true) then out[#out+1]=r end
  end
  local fields={profit='net',roi='roi',confidence='confidence',ask='cost',liquidity='liquidityCap',score='score'}
  table.sort(out,function(a,b)
    local k=fields[sort] or 'score';local x,y=a[k] or -math.huge,b[k] or -math.huge
    if sort=='name' or x==y then return a.name==b.name and a.id<b.id or a.name<b.name end
    if sort=='ask' then return x<y end;return x>y
  end)
  return out
end
function M:IsCraftCurrent(r)
  local p=self:GetPriceInfo(r.itemID)
  if not p.resaleReady or p.timestamp~=r.snapshotAt then return false end
  for id,q in pairs(r.materials or {}) do
    local current=self:QuoteAcquisition(id,q.quantity)
    if not current or current.timestamp~=q.timestamp or current.totalCost~=q.totalCost then return false end
  end
  return true
end
function M:SetCraftPlan(id,crafts)
  if self.persistenceBlocked then return false,'Read-only database' end
  if not self.db.recipes[id] or not self:Finite(crafts,0,100) or crafts%1~=0 then return false,'Select a recipe and enter 0-100 crafts' end
  local key=self.characterID..'/'..id;local count=0
  for _,p in pairs(self.db.craftPlans) do if p.character==self.characterID then count=count+1 end end
  if count>=20 and not self.db.craftPlans[key] and crafts>0 then return false,'Maximum 20 projects per character' end
  self.db.craftPlans[key]=crafts>0 and {id=id,crafts=crafts,character=self.characterID} or nil
  self:BuildCraftShopping();self:RefreshUI();return true
end
function M:BuildCraftShopping()
  local plans={}
  for _,p in pairs(self.db.craftPlans or {}) do if p.character==self.characterID then plans[#plans+1]=p end end
  table.sort(plans,function(a,b) return a.id<b.id end)
  local state=self:NewMaterialState(true);local economicState=self:NewMaterialState(false)
  local budget,errors,projects=0,{},{}
  for _,p in ipairs(plans) do
    local r=self.db.recipes[p.id]
    if r and self:Finite(p.crafts,1,100) then
      local expanded,why=self:ExpandCraft(r,p.crafts,state)
      if expanded then state=expanded else errors[#errors+1]=r.name..': '..tostring(why) end
      local economic,eWhy=self:ExpandCraft(r,p.crafts,economicState)
      if economic then economicState=economic else errors[#errors+1]=r.name..': '..tostring(eWhy) end
      local e=self:EvaluateCraft(r,p.crafts)
      projects[#projects+1]={id=p.id,name=r.name,crafts=p.crafts,status=e.status}
      if e.pass then budget=budget+math.min(e.expectedRevenue-self.db.settings.minProfit,e.expectedRevenue/(1+self.db.settings.minROI))
      else errors[#errors+1]=r.name..': '..(e.reason or 'Not a passing opportunity') end
    end
  end
  local cost,quotes=total(self,state);local rows={}
  if not cost then errors[#errors+1]=quotes;quotes={};cost=0 end
  local economicCost,economicWhy=total(self,economicState)
  if not economicCost then errors[#errors+1]=economicWhy;economicCost=0 end
  local exposure,_,reserved=self:Exposure(nil);local settings=self.db.settings
  local limit=math.min(settings.maxTransaction,settings.maxItemSpend,settings.maxExposure-exposure,
    GetMoney and GetMoney()-reserved-settings.minGoldReserve or settings.maxTransaction)
  if economicCost>limit then errors[#errors+1]='Combined projects exceed capital limits' end
  -- Retain owned materials' opportunity cost in all purchase ceilings.
  budget=math.min(budget,limit)-math.max(0,economicCost-cost)
  if economicCost>budget+math.max(0,economicCost-cost) then errors[#errors+1]='Combined material depth exceeds profit/ROI budget' end
  for id,q in pairs(quotes) do
    local name=GetItemInfo and GetItemInfo(id) or nil
    rows[#rows+1]={itemID=id,name=name or ('Item '..id),missing=state.needs[id],owned=state.used[id] or 0,
      cost=q.totalCost,source=q.source,quote=q,maxUnit=#errors==0 and math.max(0,math.floor((budget-(cost-q.totalCost))/q.purchasedQuantity)) or nil}
  end
  -- Owned-only materials must remain visible even when no purchase is needed.
  for id,n in pairs(state.used) do if n>0 and not quotes[id] then
    rows[#rows+1]={itemID=id,name=GetItemInfo and GetItemInfo(id) or ('Item '..id),missing=0,owned=n,cost=0,source='bags'}
  end end
  table.sort(rows,function(a,b) return a.itemID<b.itemID end)
  self.craftShopping={rows=rows,cost=cost,errors=errors,projects=projects,steps=state.steps,complete=#errors==0}
  return self.craftShopping
end
function M.PricingAPI.GetCraftingOpportunities()
  local out={}
  for _,r in ipairs(M.craftRows or {}) do if r.pass and M:IsCraftCurrent(r) then out[#out+1]={recipeID=r.id,itemID=r.itemID,
    quantity=r.quantity,cost=r.cost,net=r.net,roi=r.roi,confidence=r.confidence,score=r.score} end end
  return out
end
