local _,M=...
-- Versioned boundary for future summaries. No traffic, no transactions, no remote history ingestion.
M.Sync={protocol=1,maxMessage=220,minInterval=2,enabled=false}
function M.Sync:ValidateSummary(s,now)
  return type(s)=='table' and s.version==self.protocol and type(s.itemID)=='number' and s.itemID>0
    and type(s.price)=='number' and s.price>0 and s.price<1e12 and type(s.at)=='number'
    and s.at<=now+60 and s.at>=now-7200 and type(s.economy)=='string' and #s.economy<=100
end

-- VMMX1 text transfer deliberately contains ONLY market price observations.
-- It cannot alter the authoritative market model, accounting, or purchase gates.
local function validWhole(self,v,lo,hi)
  return self:Finite(v,lo,hi) and v%1==0
end
function M:ExportMarketTransfer()
  local realm,faction=self.economyID:match('^(.-)|([^|]+)$')
  if not realm or realm:find('[\t\r\n]') or faction:find('[\t\r\n]') then return nil,'Invalid economy' end
  local rows,seen={},{}
  local function add(m)
    if #rows>=100 or type(m)~='table' or not m.marketKey or seen[tostring(m.marketKey)] then return end
    local id,suffix,level,pet=m.itemID,m.itemSuffix or 0,m.itemLevel or 0,m.battlePetSpeciesID or 0
    local fair,at,conf,qty=m.fairValue,m.lastSeen,m.confidenceScore,m.latest and m.latest.quantity
    if self:Key(id,suffix,level,pet)~=m.marketKey or not validWhole(self,id,1,1e9) or not validWhole(self,suffix,-1e9,1e9)
      or not validWhole(self,level,0,1e6) or not validWhole(self,pet,0,1e9)
      or not validWhole(self,fair,1,1e12) or not validWhole(self,at,1,time()+300)
      or not validWhole(self,conf,0,100) or not validWhole(self,qty,0,1e9)
      or m.analysisIncomplete or m.cacheUntrusted or not self:MarketFresh(m) then return end
    seen[tostring(m.marketKey)]=true
    rows[#rows+1]=table.concat({id,suffix,level,pet,fair,at,conf,qty},'\t')
  end
  for key in pairs(self.db.watchlist or {}) do add(self.db.market[key]) end
  for _,o in ipairs(self.db.opportunities or {}) do add(self.db.market[o.marketKey]) end
  for _,key in ipairs(self.marketIndex or {}) do if #rows>=100 then break end; add(self.db.market[key]) end
  local header=table.concat({'VMMX1',realm,faction,time(),#rows},'\t')
  table.insert(rows,1,header)
  return table.concat(rows,'\n')
end
function M:ImportMarketTransfer(raw)
  if self.persistenceBlocked then return false,'Newer database schema; imports disabled' end
  if type(raw)~='string' or #raw>14000 or #raw<10 then return false,'Invalid summary length' end
  -- Clipboard transfers may contain Windows line endings and a final newline.
  raw=raw:gsub('\r\n','\n'):gsub('\n+$','')
  local lines={}
  for line in (raw..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
  if #lines<1 or #lines>101 then return false,'Too many rows' end
  local realm,faction=self.economyID:match('^(.-)|([^|]+)$')
  local magic,r,f,t,n=lines[1]:match('^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$')
  t,n=tonumber(t),tonumber(n)
  if magic~='VMMX1' or r~=realm or f~=faction then return false,'Incompatible realm/faction or protocol' end
  if not validWhole(self,t,time()-7*86400,time()+300) or not validWhole(self,n,0,100)
    or #lines~=n+1 then return false,'Invalid or stale transfer header' end
  local staged,unique={},{}
  for i=2,#lines do
    local fields={}
    for token in (lines[i]..'\t'):gmatch('([^\t]*)\t') do fields[#fields+1]=token end
    if #fields~=8 then return false,'Malformed observation at line '..i end
    local id,suffix,level,pet,fair,at,conf,qty=unpack(fields)
    id,suffix,level,pet=tonumber(id),tonumber(suffix),tonumber(level),tonumber(pet)
    fair,at,conf,qty=tonumber(fair),tonumber(at),tonumber(conf),tonumber(qty)
    local key=self:Key(id,suffix,level,pet)
    if not key or not validWhole(self,fair,1,1e12) or not validWhole(self,at,t-7*86400,t)
      or not validWhole(self,conf,0,100) or not validWhole(self,qty,0,1e9)
      or unique[tostring(key)] then return false,'Invalid or duplicate observation at line '..i end
    unique[tostring(key)]=true
    staged[#staged+1]={key=key,id=id,suffix=suffix,level=level,pet=pet,fair=fair,at=at,confidence=conf,quantity=qty}
  end
  local book=self.db.sharedPrices
  local updated=0
  for _,s in ipairs(staged) do
    local previous=book[s.key]
    if not previous or (tonumber(previous.at) or 0)<s.at then
      book[s.key]=s;updated=updated+1
    end
  end
  -- Bound imported price-only cache, without modifying trusted market history.
  local all={}
  for key,s in pairs(book) do
    if type(s)=='table' then all[#all+1]={key=key,at=tonumber(s.at) or 0} end
  end
  table.sort(all,function(a,b)return a.at>b.at end)
  for i=201,#all do book[all[i].key]=nil end
  if self.view=='browse' then self:BuildBrowseRows(self.db.settings.filter or '') end
  self:RefreshUI()
  return true,'Imported '..updated..' newer advisory prices; no history or trade eligibility changed'
end
