local addonName, M = ...
_G.VoidMarkMarket = M
M.name, M.version = addonName or 'VoidMarkMarket', '1.16.0'
M.eventHandlers, M.runtimeLog, M.jobs = {}, {}, {}
M.ahOpen = false
M.scanState = {running=false, phase='idle', status='No scan yet', progress=0}
function M:Now() return time() end
function M:Finite(v,lo,hi)
 return type(v)=='number' and not (issecretvalue and issecretvalue(v)) and v==v and v>=lo and v<=hi
end
function M:MarketFresh(m)
 local at=type(m)=='table' and m.lastSeen
 return self:Finite(at,1,time()+300) and time()-at<=self.db.settings.maxDataAge
end
-- A fresh asking-price snapshot alone is not evidence of resale value.
function M:CanEstimateResale(m)
  if type(m)~='table' or m.analysisIncomplete or m.cacheUntrusted or not self:MarketFresh(m)
    or not self:Finite(m.fairValue,1,1e12) then return false,'Missing, stale or untrusted market data' end
  if not self:Finite(m.observations,3,1e9) then return false,'Insufficient history: at least three independent scans required' end
  local minimum=math.max(42,self.db.settings.minConfidence or 42)
  if not self:Finite(m.confidenceScore,minimum,100) then return false,'Insufficient model confidence for a resale estimate' end
  if not self:Finite(m.volatility,0,self.db.settings.riskTolerance or 0.35) then return false,'Volatility exceeds the configured risk limit' end
  return true
end
function M:Money(v)
  v=tonumber(v) or 0
  if not self:Finite(v,-1e14,1e14) then return 'Unknown' end
  v=math.floor(v)
  local sign=v<0 and '-' or ''; v=math.abs(v)
  return sign..string.format('%dg %ds %dc',math.floor(v/10000),math.floor(v/100)%100,v%100)
end
function M:FormatDuration(s)
  s=math.max(0,math.floor(tonumber(s) or 0)); return string.format('%dm %02ds',math.floor(s/60),s%60)
end
function M:PercentText(v) return string.format('%.1f%%',(tonumber(v) or 0)*100) end
function M:Print(s)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage('|cff9f7aeaVoidMark Market:|r '..tostring(s)) end
end
function M:RefreshUI() self.uiDirty=true end
function M:Log(kind,s)
  local log=self.runtimeLog; log[#log+1]={at=time(),kind=kind,message=tostring(s)}
  if #log>200 then table.remove(log,1) end
  if self.db and self.db.settings.debug then self:Print(kind..': '..tostring(s)) end
  self:RefreshUI()
end
function M:SafeCall(label,fn,...)
  if type(fn)~='function' then return false,'API unavailable: '..label end
  local ok,a,b,c,d,e=pcall(fn,...)
  if not ok then self:Log('ERROR',label..': '..tostring(a)) end
  return ok,a,b,c,d,e
end
function M:RegisterHandler(event,fn)
  self.eventHandlers[event]=self.eventHandlers[event] or {}
  table.insert(self.eventHandlers[event],fn)
  return pcall(self.eventFrame.RegisterEvent,self.eventFrame,event)
end
function M:GetBuildSnapshot()
  local v,b,d,t=GetBuildInfo()
  return {version=v,build=b,buildDate=d,tocVersion=t,projectID=WOW_PROJECT_ID,isForever=tonumber(t)==16001}
end
function M:CanUseAuctionHouse() return self.ahOpen and type(C_AuctionHouse)=='table' end
function M:GetSecondsUntilFreshScanAllowed()
  return math.max(0,900-(time()-(self.db.lastFreshScanRequestAt or 0)))
end
function M:SetScanStatus(s,p)
  self.scanState.status=s; if p then self.scanState.progress=p end; self:RefreshUI()
end
-- Frame-budgeted jobs; callbacks run only from OnUpdate, never protected transactions.
function M:AddJob(id,step,done)
  self.jobs[id]={step=step,done=done}; return id
end
function M:CancelJob(id) self.jobs[id]=nil end
-- Per-frame work budget. A full scan runs while you stand at the Auction House,
-- so it may use a larger slice (like Auctioneer's processing priority); the
-- rest of the time background jobs stay at 4 ms. /vmm scanspeed changes it.
M.scanSpeeds={fast=12,normal=7,smooth=4}
M.budget=4
function M:FrameBudget()
  local s=self.scanState
  if s and s.running and self.ahOpen and not (InCombatLockdown and InCombatLockdown()) then
    return self.scanSpeeds[self.db and self.db.settings.scanSpeed or 'fast'] or 12
  end
  return 4
end
-- Jobs you are waiting on (bag list, a price check's results, a search) run
-- first each frame; background jobs take turns so a long scan or model job
-- never starves the rest.
M.interactiveJobs={bags=true,results=true,browse=true,owned=true}
-- Bank sync is the lowest priority: it only gets frame time left over after
-- every other job (it catches up when the scan and everything else are done).
M.lowJobs={['share-scan']=true,['share-seed']=true,['sync-count']=true}
function M:RunJobs()
  local start=debugprofilestop()
  self.budget=self:FrameBudget()
  local ids,rest,low={},{},{}
  for id in pairs(self.jobs) do
    if self.interactiveJobs[id] then ids[#ids+1]=id elseif self.lowJobs[id] then low[#low+1]=id else rest[#rest+1]=id end
  end
  table.sort(ids,function(a,b) return tostring(a)<tostring(b) end)
  local function turns(list,field)
    if #list>1 then
      table.sort(list,function(a,b) return tostring(a)<tostring(b) end)
      self[field]=(self[field] or 0)%#list+1
      for n=0,#list-1 do ids[#ids+1]=list[(self[field]-1+n)%#list+1] end
    elseif list[1] then ids[#ids+1]=list[1] end
  end
  turns(rest,'jobTurn');turns(low,'lowJobTurn')
  for _,id in ipairs(ids) do
    local job=self.jobs[id]
    if job then
    local ok,finished=pcall(job.step,start)
    if not ok or finished then
      self.jobs[id]=nil
      if not ok then self:Log('JOB ERROR',id..': '..tostring(finished))
      elseif job.done then local good,err=pcall(job.done); if not good then self:Log('JOB ERROR',err) end end
    end
    end
    if debugprofilestop()-start>=self.budget then break end
  end
end
function M:Key(itemID,suffix,level,pet)
  itemID=tonumber(itemID);suffix=tonumber(suffix or 0);level=tonumber(level or 0);pet=tonumber(pet or 0)
  if not self:Finite(itemID,1,1e9) or itemID%1~=0 or not self:Finite(suffix,-1e9,1e9)
    or suffix%1~=0 or not self:Finite(level,0,1e6) or level%1~=0 or not self:Finite(pet,0,1e9) or pet%1~=0 then return nil end
  if level~=0 or pet~=0 then return tostring(itemID)..':s'..suffix..':l'..level..':p'..pet end
  return suffix~=0 and (tostring(itemID)..':s'..suffix) or itemID
end
function M:ItemKey(m)
  return {itemID=m.itemID,itemSuffix=m.itemSuffix or 0,itemLevel=m.itemLevel or 0,battlePetSpeciesID=m.battlePetSpeciesID or 0}
end
function M:RegularQuantity(info,itemID)
  local quantity=math.max(1,math.floor(tonumber(info.quantity) or 1))
  if quantity==1 then return 1 end
  local maxStack
  if C_Item and C_Item.GetItemMaxStackSizeByID then
    local ok,v=pcall(C_Item.GetItemMaxStackSizeByID,itemID); if ok then maxStack=tonumber(v) end
  end
  if not maxStack and GetItemInfo then
    local ok,_,_,_,_,_,_,_,v=pcall(GetItemInfo,itemID); if ok then maxStack=tonumber(v) end
  end
  -- Forever may report a bogus large quantity for a single recipe. Never value
  -- a non-stackable purchase as a stack, or count unsupported inventory units.
  return math.min(quantity,maxStack and maxStack>=1 and maxStack or 1)
end
function M:SameKey(a,b)
  if type(a)~='table' or type(b)~='table' then return false end
  local key=self:Key(a.itemID,a.itemSuffix,a.itemLevel,a.battlePetSpeciesID)
  return key~=nil and key==self:Key(b.itemID,b.itemSuffix,b.itemLevel,b.battlePetSpeciesID)
end
function M:Suffix(link)
  local s=type(link)=='string' and link:match('|Hitem:([^|]+)|h')
  if not s then return nil end
  local fields={}; for f in (s..':'):gmatch('(.-):') do fields[#fields+1]=f; if #fields==7 then break end end
  return tonumber(fields[7]) or 0
end
function M:IsCommodity(key)
  if C_AuctionHouse.GetItemKeyInfo then
    local ok,info=pcall(C_AuctionHouse.GetItemKeyInfo,key)
    if ok and type(info)=='table' and type(info.isCommodity)=='boolean' then return info.isCommodity end
  end
  return nil -- Unknown classification must never enable a purchase.
end
M.eventFrame=CreateFrame('Frame')
M.eventFrame:RegisterEvent('ADDON_LOADED'); M.eventFrame:RegisterEvent('PLAYER_LOGIN')
M.eventFrame:SetScript('OnEvent',function(_,event,...)
  if event=='ADDON_LOADED' then
    if (...)~=M.name then return end; M:InitializeDatabase(); return
  elseif event=='PLAYER_LOGIN' then
    if not M.db then M:InitializeDatabase() end
    M:RegisterHandler('AUCTION_HOUSE_DISABLED',function() end)
    M:RunAPIProbe(); M:InitializeUI(); M:InitializeMinimapButton(); M:InitializePriceTooltips(); M:StartSharing()
  end
  if event=='AUCTION_HOUSE_DISABLED' then event='AUCTION_HOUSE_CLOSED' end
  local args={...}
  local t0=M.perf and debugprofilestop()
  for _,fn in ipairs(M.eventHandlers[event] or {}) do
    local ok,err=pcall(fn,M,event,unpack(args)); if not ok then M:Log('EVENT ERROR',event..': '..tostring(err)) end
  end
  if t0 then M:PerfAdd(event,debugprofilestop()-t0) end
end)
-- /vmm perf: 10 seconds of VoidMark Market CPU use by event and update step.
function M:PerfAdd(name,ms)
  local p=self.perf;if not p then return end
  local e=p.items[name] or {total=0,max=0,count=0};p.items[name]=e
  e.total=e.total+ms;e.count=e.count+1;if ms>e.max then e.max=ms end
end
function M:StartPerf(seconds)
  self.perf={items={},started=GetTime(),until_=GetTime()+(seconds or 10)}
  self:Print('Measuring VoidMark Market CPU for '..(seconds or 10)..' seconds...')
end
function M:FinishPerf()
  local p=self.perf;self.perf=nil;if not p then return end
  local list,total={},0
  for k,e in pairs(p.items) do list[#list+1]={k,e};total=total+e.total end
  table.sort(list,function(a,b) return a[2].total>b[2].total end)
  local span=math.max(1,GetTime()-p.started)
  self:Print(('CPU: %.1f ms/s total over %ds'):format(total/span,span))
  for i=1,math.min(6,#list) do
    local k,e=list[i][1],list[i][2]
    self:Print(('  %s: %.1f ms/s, worst %.1f ms, %d calls'):format(k,e.total/span,e.max,e.count))
  end
end
local tick=0
M.eventFrame:SetScript('OnUpdate',function(_,elapsed)
  if not M.db then return end
  local p=M.perf;local t=p and debugprofilestop()
  local function mark(name) if p then local now=debugprofilestop();M:PerfAdd(name,now-t);t=now end end
  if next(M.jobs) then M:RunJobs();mark('jobs') end; tick=tick+elapsed
  if tick<0.1 then return end; tick=0
  M:PumpQueue(); M:ExecutionTick();mark('queue'); M:PumpSharing();mark('sync')
  if M.liveBrowse and M.liveBrowse.received and not M.liveBrowse.expired and GetTime()-M.liveBrowse.received>10 then
    M.liveBrowse.expired=true;M:RefreshUI()
  end
  -- Bag pricing only while Selling is on screen (it used to re-run with the
  -- window closed whenever item data loaded).
  if M.bagsDirty and M.view=='selling' and M.window and M.window:IsShown() then M.bagsDirty=false; M:RefreshInventory();mark('bags') end
  if M.ItemNameTick then M:ItemNameTick();mark('names') end
  if M.SellTick then M:SellTick() end
  if M.uiDirty and M.RenderUI then M:RenderUI();mark('render') end
  if p and GetTime()>=p.until_ then M:FinishPerf() end
end)
SLASH_VOIDMARKMARKET1='/vmm'; SLASH_VOIDMARKMARKET2='/voidmarkmarket'
SlashCmdList.VOIDMARKMARKET=function(msg)
  local raw=(msg or ''):match('^%s*(.-)%s*$')
  msg=raw:lower()
  if msg=='peer' or msg:match('^peer%s') then M:Print(M:PairPeer(raw:match('^%S+%s+(.+)$')))
  elseif msg=='perf' then M:StartPerf(10)
  elseif msg=='scanspeed' or msg:match('^scanspeed%s') then
    local v=msg:match('^scanspeed%s+(%a+)$')
    if v and M.scanSpeeds[v] then M.db.settings.scanSpeed=v end
    M:Print('Scan speed: '..(M.db.settings.scanSpeed or 'fast')..' ('..(M.scanSpeeds[M.db.settings.scanSpeed or 'fast'])..' ms per frame while scanning). Options: fast, normal, smooth')
  elseif msg=='version' then M:Print('Version '..M.version..' | sync partner: '..tostring(M.db.syncPeer or 'not paired'))
  elseif msg=='scan' then M:RequestFreshScan()
  elseif msg=='cached' then M:AnalyzeCachedSnapshot()
  elseif msg=='diag' then M:SetView('diagnostics')
  elseif msg=='report' then M:ShowReport()
  elseif msg=='probe' then M:RunAPIProbe()
  elseif msg=='craft' then M:RebuildCrafting();M:SetView('crafting')
  elseif msg=='craftscan' then M:CaptureProfession()
  elseif msg=='materials' then M:BuildCraftShopping();M:SetView('materials')
  elseif msg=='de' or msg=='disenchant' then M:ShowDisenchantWindow('bags')
  elseif msg=='de ah' then M:ShowDisenchantWindow('market')
  elseif msg=='de tooltip' then M.db.settings.tooltipDisenchant=M.db.settings.tooltipDisenchant==false;M:Print('Disenchant tooltip '..(M.db.settings.tooltipDisenchant and 'on' or 'off'))
  elseif msg=='gold' then M:SetView('goldmaking')
  elseif msg=='deal' or msg:match('^deal%s') then
    local v=tonumber(msg:match('^deal%s+(%d+)'))
    if v and v>=10 and v<=100 then M.db.settings.dealPercent=math.floor(v) end
    M:Print('Deals show green at '..M:DealPercent()..'% of the 30-day average or less. Change with /vmm deal 50 (10-100).')
  elseif msg=='flipmax' or msg:match('^flipmax%s') then
    local v=tonumber(msg:match('^flipmax%s+([%d%.]+)'))
    if v then M.db.settings.flipMaxBuy=v>0 and math.floor(v*100+0.5) or 0 end
    local max=M:FlipMaxBuy()
    M:Print(max and ('Search terms only show items at '..M:Coins(max)..' or less. /vmm flipmax 0 turns it off.') or 'No max price on search terms. Set one in silver: /vmm flipmax 15')
  elseif msg=='flips' or msg=='ledger' then M:ShowFlipLedger()
  elseif msg=='flipstarter' then
    local n=M:AddFlipStarter();M:Print(n..' starter search terms added to your Shopping list (old starter terms replaced).');M:RefreshUI()
  elseif msg=='debug' then M.db.settings.debug=not M.db.settings.debug; M:Print('Debug '..tostring(M.db.settings.debug))
  else M:ToggleUI() end
end

