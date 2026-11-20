local _,M=...
-- Realm name without spaces. WoW Forever can return an EMPTY normalized realm
-- name while addons load; '' is not nil, so "a or b" kept it and all prices
-- were looked up under realm "" (every tooltip: "No price yet").
function M:RealmName()
  local function given(f) if type(f)~='function' then return nil end local ok,v=pcall(f) if ok and type(v)=='string' and v~='' then return v end end
  return (given(GetNormalizedRealmName) or given(GetRealmName) or ''):gsub('%s','')
end
M.defaults={debug=false,maxTransaction=100000,maxItemSpend=500000,maxQuantity=20,
 maxExposure=2000000,minProfit=100,minROI=0.20,minConfidence=42,minLiquidity=15,
 riskTolerance=0.35,ahCut=0.05,depositReserve=100,maxDataAge=7200,historyDays=90,filter='',sort='score',minGoldReserve=0,sellStrategy='competitive',sellMinMargin=0,sellUndercut=1,postDuration=3,dealPercent=60,flipMaxBuy=0,shopMinLevel=0,shopMaxLevel=0}
function M:InitializeDatabase()
  if type(VoidMarkMarketDB)~='table' then VoidMarkMarketDB={} end
  local root=VoidMarkMarketDB
  if (tonumber(root.schemaVersion) or 0)>1 then
    self.persistenceBlocked=true; root={} -- analyze only in memory; leave newer saved schema untouched
    self:Print('Saved data was created by a newer addon. This session is read-only; update before trading.')
  end
  self.root=root
  self.loadedSavedMarker=type(root.persistenceMarker)=='table'
  root.persistenceMarker=root.persistenceMarker or {createdAt=time(),version=self.version}
  root.settings=type(root.settings)=='table' and root.settings or {}
  for k,v in pairs(self.defaults) do
    if type(root.settings[k])~=type(v) then root.settings[k]=v end
    if type(v)=='number' and (root.settings[k]~=root.settings[k] or root.settings[k]<0 or root.settings[k]>1e12) then root.settings[k]=v end
  end
  root.settings.safeMode=nil -- retire only the obsolete switch
  root.settings.itemPostBid=nil -- 1.9.10 experiment: copper, not the bid, was the cause
  root.settings.ahCut=math.min(0.30,root.settings.ahCut)
  root.settings.riskTolerance=math.min(2,root.settings.riskTolerance)
  root.economies=type(root.economies)=='table' and root.economies or {}
  -- One realm name, always without spaces. The game sometimes gives
  -- "CAMWOW US2 Realm 8 PvP" and sometimes "CAMWOWUS2Realm8PvP" (the
  -- normalized name isn't ready yet at some logins), and before 1.23.29 each
  -- spelling got its own copy of your data, so every login saw only half.
  local realm=self:RealmName()
  local faction=UnitFactionGroup('player') or 'Unknown'
  self.economyID=realm..'|'..faction
  self.characterID=(UnitName('player') or 'Unknown')..'|'..realm
  if not self.persistenceBlocked and self.MergeSplitEconomies then
    local ok,err=pcall(self.MergeSplitEconomies,self,root,self.economyID)
    if not ok then self.economyMergeError=tostring(err) end
  end
  local db=root.economies[self.economyID]
  if type(db)~='table' then db={}; root.economies[self.economyID]=db end
  self.db=db; db.settings=root.settings
  for _,k in ipairs({'market','scans','queries','ownedQueries','opportunities','ledger','inventory','mailSeen','pending','totals','watchlist','banker','sharedPrices','reviewQueue','sellFloors','postQueue','financialDays','wealthHistory','sellStacks','liveSeen','postHistory','sellFavourites','recentSearches','itemNames'}) do
    if type(db[k])~='table' then db[k]={} end
  end
  db.scanSequence=tonumber(db.scanSequence) or 0; db.ledgerSequence=tonumber(db.ledgerSequence) or 0
  -- Keep the legacy global declared in the TOC. User imports it once as documented.
  -- Adopt existing records by reference, without deleting/rewriting the old root.
  if type(TaliaaTradeBetaDB)=='table' and not root.legacyImported then
    local legacy=TaliaaTradeBetaDB
    if type(legacy.market)=='table' then
      for k,m in pairs(legacy.market) do if type(m)=='table' and not db.market[k] then db.market[k]=m end end
    end
    db.scanSequence=math.max(db.scanSequence,tonumber(legacy.scanSequence) or 0)
    db.lastFreshScanRequestAt=legacy.lastFreshScanRequestAt
    db.latestScan=db.latestScan or legacy.latestScan
    root.legacyImported={at=time(),economy=self.economyID,schema=legacy.schemaVersion}
  end
  if self.PruneLiveSeen then self:PruneLiveSeen() end
  -- 1.20.3: fill the Flip Ledger from buys and sales recorded before it existed.
  if not self.persistenceBlocked and self.BackfillFlips and (tonumber(db.flipBackfill) or 0)<1 then
    local ok,buys,sales=pcall(self.BackfillFlips,self)
    if ok then db.flipBackfill=1;if (buys or 0)+(sales or 0)>0 then self:Print(('Flip Ledger: added %d earlier buys and %d earlier sales from your history.'):format(buys,sales)) end end
  end
  self:InitializeSharing()
  db.currentBuild=self:GetBuildSnapshot()
  root.schemaVersion=1; db.schemaVersion=1
  self.exposureDirty=true
  self:RebuildIndexes()
  -- One background pass at login converts history saved by older versions.
  if not self.persistenceBlocked and db.historyFormat~=2 then
    self:PruneDatabase(function() db.historyFormat=2 end)
  end
  if self.InitializeCrafting then self:InitializeCrafting() end
  -- Times saved while the PC clock was ahead: pull them back (background, every login).
  if not self.persistenceBlocked then self:RepairFutureTimes() end
  -- Pending spend is persistent. Reload/close never changes an uncertain purchase to failed.
  for _,p in pairs(db.pending) do
    if type(p)=='table' then
      if p.status=='pending' then p.status='unknown' end
      -- SavedVariables may serialize aliases as independent copies. Canonicalize
      -- unresolved orders by ID so the visible ledger receives later resolutions.
      for i,e in ipairs(db.ledger) do if type(e)=='table' and e.id==p.id then db.ledger[i]=p; break end end
    end
  end
  self:RebuildOpportunities()
end
function M:RebuildIndexes()
  self.marketIndex={}; self.itemIndex={}; self.nameIndex={}; local cursor=nil
  self:AddJob('index',function(start)
    while true do
      local k,m=next(self.db.market,cursor); cursor=k
      if k==nil then return true end
      if type(m)=='table' and tonumber(m.itemID) and type(m.latest)=='table' and type(m.history or {})=='table' then
        m.history=m.history or {}; self.marketIndex[#self.marketIndex+1]=k
        self.itemIndex[m.itemID]=self.itemIndex[m.itemID] or {}; table.insert(self.itemIndex[m.itemID],k)
        if m.name then if self.nameIndex[m.name]==nil then self.nameIndex[m.name]=k else self.nameIndex[m.name]=false end end
        if type(m.suffixFloors)=="table" then for n in pairs(m.suffixFloors) do if n~=m.name and self.nameIndex[n]==nil then self.nameIndex[n]=k end end end
      end
      if debugprofilestop()-start>=self.budget then return false end
    end
  end,function() self:RebuildOpportunities(); if self.RebuildCrafting then self:RebuildCrafting() end; if self.view=='browse' then self:BuildBrowseRows(self.db.settings.filter) end; self:RefreshUI() end)
end
function M:GetMarket(itemID)
  local keys=self.itemIndex[tonumber(itemID)] or {}; local best
  for _,k in ipairs(keys) do local m=self.db.market[k]; if not best or (m.lastSeen or 0)>(best.lastSeen or 0) then best=m end end
  return best
end
function M:GetMarketVariants(itemID)
  local out={}; for _,k in ipairs(self.itemIndex[tonumber(itemID)] or {}) do out[#out+1]=self.db.market[k] end; return out
end
function M:PruneDatabase(done)
  local cursor=nil; local cutoff=time()-self.db.settings.historyDays*86400
  self:AddJob('prune',function(start)
    while true do
      local k,m=next(self.db.market,cursor); cursor=k; if k==nil then return true end
      if type(m)=='table' and type(m.history)=='table' then
        while #m.history>1 and type(m.history[1])=='table' and (tonumber(m.history[1].at) or 0)<cutoff do table.remove(m.history,1) end
        -- Retain the last useful price and aggregate history even for absent markets.
        if (tonumber(m.lastSeen) or 0)<cutoff then m.archived=true end
        -- Older versions stored full snapshots in history; shrink them in place.
        for i,h in ipairs(m.history) do if type(h)=='table' and h.q10~=nil then m.history[i]=self.SlimObservation(h) end end
      end
      if debugprofilestop()-start>=self.budget then return false end
    end
  end,done)
end

-- Saved times in the future (PC clock was ahead for a while) make prices look
-- newer than they are, stop sync pages from being accepted, and confuse
-- "last seen" ages. Walk the saved data in the background and pull any
-- 'at' / 'lastSeen' / '...At' time that's ahead of now back to now.
-- '...Until' fields (guards that are meant to be in the future) are left alone.
local function timeKey(k)
  if type(k)~='string' then return false end
  if k=='at' or k=='lastSeen' or k=='firstSeen' then return true end
  return k:sub(-2)=='At' and not k:find('Until',1,true)
end
function M:RepairFutureTimes(done)
  local now=time();local limit=now+300;local far=now+20*365*86400
  local stack={self.db};local seen={};local fixed=0
  self:AddJob('futuretimes',function(start)
    while true do
      local t=table.remove(stack);if t==nil then return true end
      if not seen[t] then
        seen[t]=true
        for k,v in pairs(t) do
          if type(v)=='table' then stack[#stack+1]=v
          elseif type(v)=='number' and v>limit and v<=far and timeKey(k) then t[k]=now;fixed=fixed+1 end
        end
      end
      if debugprofilestop()-start>=self.budget then return false end
    end
  end,function() self.db.futureTimesFixed=(self.db.futureTimesFixed or 0)+fixed;if done then done(fixed) end end)
end


-- 1.23.29: fold the copies made under other spellings of this realm (spaces)
-- into the one copy. Nothing is thrown away: lists are joined without
-- duplicates, and for prices the newest reading wins.
local function squash(x) return tostring(x or ''):gsub('%s',''):lower() end
local function fixChar(v,canon)
  if type(v)~='string' then return v end
  local name,realm=v:match('^(.-)|(.+)$')
  if name and squash(realm)==squash(canon) then return name..'|'..canon end
  return v
end
local function newer(a,b,field)
  return (tonumber(type(a)=='table' and a[field]) or 0)>=(tonumber(type(b)=='table' and b[field]) or 0)
end
local NEWEST={market='lastSeen',liveSeen='at',sharedPrices='at',shareBases='at',banker=nil}
local UNION={'itemNames','keyNames','recipes','mailSeen','mailNameless','partnerBuys','dailyLowsBase','shopTerms','shoppingLists',
  'sellFavourites','sellFloors','sellStacks','watchlist','flipSyncSent','ownedSnapshot','reviewQueue','postQueue'}
function M:MergeSplitEconomies(root,canonID)
  local realm,faction=canonID:match('^(.-)|([^|]+)$')
  if not realm then return 0 end
  local merged=0
  for id,other in pairs(root.economies) do
    local r,f=tostring(id):match('^(.-)|([^|]+)$')
    -- A copy saved under an empty realm name (see RealmName) is this realm too.
    if id~=canonID and type(other)=='table' and f==faction and (squash(r)==squash(realm) or (r=='' and realm~='')) then
      local db=root.economies[canonID]
      if type(db)~='table' then
        root.economies[canonID]=other;root.economies[id]=nil;merged=merged+1
        db=other
      else
        self:MergeEconomyInto(db,other,realm)
        root.economies[id]=nil;merged=merged+1
      end
    end
  end
  -- Character names saved inside entries use the old spelling too.
  if merged>0 then
    local db=root.economies[canonID]
    for _,t in ipairs({'ledger','pending','flips'}) do
      for _,e in pairs(type(db[t])=='table' and db[t] or {}) do
        if type(e)=='table' then e.character=fixChar(e.character,realm);e.char=fixChar(e.char,realm) end
      end
    end
    if type(db.inventory)=='table' then
      local inv={}
      for k,lot in pairs(db.inventory) do
        local c,rest=tostring(k):match('^(.-)/(.+)$')
        if type(lot)=='table' then lot.character=fixChar(lot.character,realm) end
        local nk=c and (fixChar(c,realm)..'/'..rest) or k
        if inv[nk]==nil then inv[nk]=lot end
      end
      db.inventory=inv
    end
    if type(db.wealthHistory)=='table' then
      local w={}
      for k,list in pairs(db.wealthHistory) do
        local nk=fixChar(k,realm)
        if type(w[nk])=='table' and type(list)=='table' then for _,x in ipairs(list) do table.insert(w[nk],x) end
          table.sort(w[nk],function(a,b) return (tonumber(type(a)=='table' and a.at) or 0)<(tonumber(type(b)=='table' and b.at) or 0) end)
        else w[nk]=list end
      end
      db.wealthHistory=w
    end
    root.economyMerge={at=time(),economy=canonID,merged=merged}
  end
  return merged
end

function M:MergeEconomyInto(db,other,realm)
  local function tbl(t,k) if type(t[k])~='table' then t[k]={} end return t[k] end
  -- Prices: newest reading wins.
  for name,field in pairs(NEWEST) do
    local dst,src=tbl(db,name),other[name]
    if type(src)=='table' then
      for k,v in pairs(src) do if dst[k]==nil or not newer(dst[k],v,field) then dst[k]=v end end
    end
  end
  -- Plain lookups and "already seen" sets: union.
  for _,name in ipairs(UNION) do
    local dst,src=tbl(db,name),other[name]
    if type(src)=='table' then for k,v in pairs(src) do if dst[k]==nil then dst[k]=v end end end
  end
  -- Daily lows: per item per day, the lower price.
  do local dst,src=tbl(db,'dailyLows'),other.dailyLows
    if type(src)=='table' then for k,days in pairs(src) do
      if type(dst[k])~='table' then dst[k]=days elseif type(days)=='table' then
        for d,v in pairs(days) do local cur=tonumber(dst[k][d]);if not cur or (tonumber(v) and v<cur) then dst[k][d]=v end end
      end end end
  end
  -- Post history: join each item's list, oldest first, no repeats.
  do local dst,src=tbl(db,'postHistory'),other.postHistory
    if type(src)=='table' then for k,list in pairs(src) do
      if type(dst[k])~='table' then dst[k]=list elseif type(list)=='table' then
        local seen={}
        for _,e in ipairs(dst[k]) do if type(e)=='table' then seen[tostring(e.at)..':'..tostring(e.unit)..':'..tostring(e.quantity)]=true end end
        for _,e in ipairs(list) do if type(e)=='table' and not seen[tostring(e.at)..':'..tostring(e.unit)..':'..tostring(e.quantity)] then table.insert(dst[k],e) end end
        table.sort(dst[k],function(a,b) return (tonumber(a.at) or 0)>(tonumber(b.at) or 0) end)
        while #dst[k]>20 do table.remove(dst[k]) end
      end end end
  end
  -- Ledger and flips: append the other copy's entries with new ids, skipping
  -- any that are the same event (same time, item, kind, amount).
  local function fp(e) return table.concat({tostring(e.kind or e.type or e.source),tostring(e.marketKey or e.key or e.name),tostring(e.at),tostring(e.quantity or e.qty),tostring(e.gross or e.cost or e.amount or e.price)},'|') end
  for _,name in ipairs({'ledger','flips'}) do
    local dst,src=tbl(db,name),other[name]
    if type(src)=='table' then
      local seen,maxID={},0
      for _,e in pairs(dst) do if type(e)=='table' then seen[fp(e)]=true;maxID=math.max(maxID,tonumber(e.id) or 0) end end
      local add={}
      for _,e in pairs(src) do if type(e)=='table' and not seen[fp(e)] then seen[fp(e)]=true;add[#add+1]=e end end
      table.sort(add,function(a,b) return (tonumber(a.at) or 0)<(tonumber(b.at) or 0) end)
      for _,e in ipairs(add) do maxID=maxID+1;e.id=maxID;table.insert(dst,e) end
      table.sort(dst,function(a,b) return (tonumber(a.at) or 0)<(tonumber(b.at) or 0) end)
      if name=='ledger' then db.ledgerSequence=math.max(tonumber(db.ledgerSequence) or 0,tonumber(other.ledgerSequence) or 0,maxID) end
      if name=='flips' then
        db.flipSequence=math.max(tonumber(db.flipSequence) or 0,tonumber(other.flipSequence) or 0,maxID)
        -- Renumbered flips aren't new buys: don't re-send them to the other character.
        if #add>0 and type(db.flipSyncSent)=='table' then db.flipSyncSent.high=math.max(tonumber(db.flipSyncSent.high) or 0,maxID) end
      end
    end
  end
  -- Mail order and scans: join, no repeats.
  do local dst,src=tbl(db,'mailOrder'),other.mailOrder
    if type(src)=='table' then local seen={};for _,k in ipairs(dst) do seen[k]=true end
      for _,k in ipairs(src) do if not seen[k] then seen[k]=true;table.insert(dst,k) end end end
  end
  do local dst,src=tbl(db,'scans'),other.scans
    if type(src)=='table' then for _,x in ipairs(src) do table.insert(dst,x) end
      table.sort(dst,function(a,b) return (tonumber(a.responseAt) or 0)<(tonumber(b.responseAt) or 0) end)
      while #dst>20 do table.remove(dst,1) end end
  end
  -- Recent searches: keep the newest 20.
  do local dst,src=tbl(db,'recentSearches'),other.recentSearches
    if type(src)=='table' then local seen={};for _,x in ipairs(dst) do seen[tostring(type(x)=='table' and x.text or x)]=true end
      for _,x in ipairs(src) do local k=tostring(type(x)=='table' and x.text or x);if not seen[k] then seen[k]=true;table.insert(dst,x) end end
      while #dst>20 do table.remove(dst) end end
  end
  -- Totals: both copies counted different buys.
  if type(other.totals)=='table' then local t=tbl(db,'totals')
    for k,v in pairs(other.totals) do if tonumber(v) then t[k]=(tonumber(t[k]) or 0)+v end end end
  -- Everything else the canonical copy lacks: take it as is.
  for k,v in pairs(other) do if db[k]==nil then db[k]=v end end
  for _,k in ipairs({'scanSequence','ledgerSequence'}) do db[k]=math.max(tonumber(db[k]) or 0,tonumber(other[k]) or 0) end
  local function scanAt(x) return type(x)=='table' and (tonumber(x.responseAt) or tonumber(x.startedAt) or tonumber(x.at)) or 0 end
  if scanAt(other.latestScan)>scanAt(db.latestScan) then db.latestScan=other.latestScan end
  if type(other.banker)=='table' and (tonumber(other.banker.latest and other.banker.latest.at) or 0)>(tonumber(db.banker and db.banker.latest and db.banker.latest.at) or 0) then db.banker=other.banker end
end
