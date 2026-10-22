local _,M=...
-- All amounts are copper. Recorded balances are observations, not trading profit.
function M:RecordFinancialSale(entry,knownRevenue,basis)
  local day=math.floor(time()/86400)
  local days=self.db.financialDays
  local bucket=days[day] or {revenue=0,realized=0,fees=0,basis=0,uncosted=0,sales=0}
  days[day]=bucket
  bucket.revenue=bucket.revenue+entry.gross-entry.fee
  bucket.realized=bucket.realized+knownRevenue-basis
  bucket.fees=bucket.fees+entry.fee;bucket.basis=bucket.basis+basis
  bucket.uncosted=bucket.uncosted+entry.gross-entry.fee-knownRevenue
  bucket.sales=bucket.sales+1
  for d in pairs(days) do if type(d)=='number' and d<day-365 then days[d]=nil end end
end
function M:GetFinancialPeriods()
  local result={};local today=math.floor(time()/86400)
  for _,length in ipairs({1,7,30}) do
    local p={days=length,revenue=0,realized=0,fees=0,basis=0,uncosted=0,sales=0}
    for day,b in pairs(self.db.financialDays or {}) do
      if type(day)=='number' and day<=today and day>today-length and type(b)=='table' then
        for _,field in ipairs({'revenue','realized','fees','basis','uncosted','sales'}) do
          if self:Finite(b[field],-1e14,1e14) then p[field]=p[field]+b[field] end
        end
      end
    end
    p.roi=p.basis>0 and p.realized/p.basis or nil
    result[#result+1]=p
  end
  return result
end
function M:RecordWealthSample()
  if not self.db or self.persistenceBlocked or not GetMoney then return end
  local now=time()
  if self.lastWealthAt and now-self.lastWealthAt<60 then return end
  self.lastWealthAt=now
  local _,portfolio=self:GetPortfolioRows()
  local gold=GetMoney()
  if not self:Finite(gold,0,1e14) then return end
  local history=self.db.wealthHistory[self.characterID] or {}
  self.db.wealthHistory[self.characterID]=history
  local sample={at=now,gold=gold,estimatedNet=portfolio.estimatedNet,
    unpricedCost=portfolio.unvaluedCost,cost=portfolio.cost}
  local prior=history[#history]
  if prior and math.floor(prior.at/3600)==math.floor(now/3600) then history[#history]=sample
  else history[#history+1]=sample end
  while #history>720 do table.remove(history,1) end
end
M:RegisterHandler('PLAYER_MONEY',function(self) self:RecordWealthSample();self:RefreshUI() end)
M:RegisterHandler('PLAYER_LOGIN',function(self) self:RecordWealthSample() end)
M:RegisterHandler('PLAYER_LOGOUT',function(self) self.lastWealthAt=nil;self:RecordWealthSample() end)

function M:GetPriceHistory(key)
  local m=self.db.market[key];local points={}
  if not m then return points end
  for _,h in ipairs(m.history or {}) do
    if type(h)=='table' and self:Finite(h.at,1,time()+300) and self:Finite(h.median,1,1e12) then
      points[#points+1]={at=h.at,value=h.median}
    end
  end
  table.sort(points,function(a,b)return a.at<b.at end)
  while #points>60 do table.remove(points,1) end
  return points
end

local presets={
  conservative={minROI=0.30,minProfit=500,minConfidence=60,minLiquidity=30,riskTolerance=0.20},
  balanced={minROI=0.20,minProfit=100,minConfidence=42,minLiquidity=15,riskTolerance=0.35},
  exploratory={minROI=0.15,minProfit=100,minConfidence=42,minLiquidity=15,riskTolerance=0.50}}
function M:ApplySniperPreset(name)
  local preset=presets[name]
  if self.persistenceBlocked or not preset then return false end
  for k,v in pairs(preset) do self.db.settings[k]=v end
  self.db.settings.sniperPreset=name
  -- Changes to model gates invalidate a previously prepared purchase.
  if self.execution and self.execution.state~='pending' and self.execution.state~='idle' then
    self:InvalidateQuote('Risk preset changed; revalidate')
  end
  self:RebuildOpportunities();self:RefreshUI();return true
end

function M:InspectLiveMarket(row)
  local m=row and self.db.market[row.marketKey]
  if not m or not self.ahOpen then return false,'Select a local market with the Auction House open' end
  if self:HasUnresolvedPurchase() or (self.execution and
    (self.execution.state=='quoting' or self.execution.state=='quoted' or self.execution.state=='validating' or self.execution.state=='ready')) then
    return false,'Finish or discard the current purchase review before searching'
  end
  local token=(self.liveBrowseToken or 0)+1;self.liveBrowseToken=token
  self.liveBrowse={marketKey=m.marketKey,status='Searching',rows={}}
  local ok,why=self:Search(m,20,function(result)
    if token~=self.liveBrowseToken then return end
    self.liveBrowse={marketKey=m.marketKey,status='Complete',rows=result.rows,received=GetTime(),commodity=result.commodity}
    self:RefreshUI()
  end,function(reason)
    if token==self.liveBrowseToken then self.liveBrowse={marketKey=m.marketKey,status=reason,rows={}};self:RefreshUI() end
  end,function() return token==self.liveBrowseToken and self.ahOpen end)
  if not ok then self.liveBrowse.status=why or 'Search unavailable; retry after active query' end
  self:RefreshUI();return ok,why
end

function M:SetPreferredStack(key,size)
  if self.persistenceBlocked or not self.db.market[key] then return false,'Select a local item first' end
  if size~=nil and (not self:Finite(size,1,1000) or size%1~=0) then return false,'Stack size must be a whole number from 1 to 1000' end
  local count=0;for _ in pairs(self.db.sellStacks) do count=count+1 end
  if size and not self.db.sellStacks[key] and count>=300 then return false,'300 stack preferences maximum' end
  self.db.sellStacks[key]=size;self:RefreshUI();return true
end
function M:StackPlanText(row)
  if not row or not row.marketKey then return '' end
  local wanted=self.db.sellStacks[row.marketKey]
  local qty=tonumber(row.quantity)
  if not wanted or not qty or qty<1 then return 'Set an optional stack size below; split and post in the native AH.' end
  local m=self.db.market[row.marketKey];local maxStack
  if m and GetItemInfo then local _,_,_,_,_,_,_,limit=GetItemInfo(m.itemID);maxStack=tonumber(limit) end
  if not maxStack or maxStack<1 then return 'Item stack limit unavailable; wait for item metadata.' end
  local size=math.min(wanted,maxStack,qty)
  local full=math.floor(qty/size);local remainder=qty%size
  return 'Stack plan: '..full..' x '..size..(remainder>0 and (' + '..remainder..' remainder') or '')..
    (size<wanted and ' (limited by item/stock)' or '')..'. Native posting only.'
end
M:RegisterHandler('AUCTION_HOUSE_CLOSED',function(self)
  self.liveBrowseToken=(self.liveBrowseToken or 0)+1;self.liveBrowse=nil
end)
function M:LiveMarketText(key)
  local live=self.liveBrowse
  if not live or live.marketKey~=key then return 'Click LIVE COMPARE to request current listings.' end
  if not live.received then return tostring(live.status) end
  local age=GetTime()-live.received
  local text=(age>10 and 'EXPIRED' or 'LIVE OBSERVATION')..' - '..math.floor(age)..'s old; revalidate again before any purchase.'
  for i=1,math.min(4,#live.rows) do
    local r=live.rows[i]
    text=text..'\n'..r.quantity..' units @ '..self:Money(r.unit)..' | total '..self:Money(r.total)
  end
  if #live.rows==0 then text=text..'\nNo available buyout listings.' end
  return text
end
