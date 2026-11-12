local _,M=...
-- Legacy advisory summary validation, retained for compatibility. Live pairing is in Sharing.lua.
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
function M:ExportMarketTransfer(page)
  local realm,faction=self.economyID:match('^(.-)|([^|]+)$')
  if not realm or realm:find('[\t\r\n]') or faction:find('[\t\r\n]') then return nil,'Invalid economy' end
  local rows,seen={},{}
  local function add(m)
    if #rows>=100 or type(m)~='table' or not m.marketKey or seen[tostring(m.marketKey)] then return end
    local id,suffix,level,pet=m.itemID,m.itemSuffix or 0,m.itemLevel or 0,m.battlePetSpeciesID or 0
    local floor=m.latest and m.latest.floor
    if not validWhole(self,floor,1,1e12) then return end
    local fair,at,conf,qty=m.fairValue,m.lastSeen,m.confidenceScore,m.latest and m.latest.quantity
    if self:Key(id,suffix,level,pet)~=m.marketKey or not validWhole(self,id,1,1e9) or not validWhole(self,suffix,-1e9,1e9)
      or not validWhole(self,level,0,1e6) or not validWhole(self,pet,0,1e9)
      or not validWhole(self,fair,1,1e12) or not validWhole(self,at,1,time()+300)
      or not validWhole(self,conf,0,100) or not validWhole(self,qty,0,1e9)
      or m.analysisIncomplete or m.cacheUntrusted or not self:MarketFresh(m) then return end
    seen[tostring(m.marketKey)]=true
    rows[#rows+1]=table.concat({id,suffix,level,pet,fair,at,conf,qty,floor,self:CanEstimateResale(m) and 1 or 0},'\t')
  end
  local pages=1
  if page then
    if not validWhole(self,page,1,100000) then return nil,'Invalid export page' end
    local keys={};for _,key in ipairs(self.marketIndex or {}) do keys[#keys+1]=key end
    table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
    pages=math.max(1,math.ceil(#keys/100));page=math.min(page,pages)
    for i=(page-1)*100+1,math.min(#keys,page*100) do add(self.db.market[keys[i]]) end
  else
  for key in pairs(self.db.watchlist or {}) do add(self.db.market[key]) end
  for _,o in ipairs(self.db.opportunities or {}) do add(self.db.market[o.marketKey]) end
  for _,key in ipairs(self.marketIndex or {}) do if #rows>=100 then break end; add(self.db.market[key]) end
  end
  local header=table.concat({'VMMX2',realm,faction,time(),#rows},'\t')
  table.insert(rows,1,header)
  return table.concat(rows,'\n'),nil,page or 1,pages
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
  if (magic~='VMMX1' and magic~='VMMX2') or r~=realm or f~=faction then return false,'Incompatible realm/faction or protocol' end
  if not validWhole(self,t,time()-7*86400,time()+300) or not validWhole(self,n,0,100)
    or #lines~=n+1 then return false,'Invalid or stale transfer header' end
  local staged,unique={},{}
  for i=2,#lines do
    local fields={}
    for token in (lines[i]..'\t'):gmatch('([^\t]*)\t') do fields[#fields+1]=token end
    if #fields~=(magic=='VMMX2' and 10 or 8) then return false,'Malformed observation at line '..i end
    local id,suffix,level,pet,fair,at,conf,qty=unpack(fields)
    id,suffix,level,pet=tonumber(id),tonumber(suffix),tonumber(level),tonumber(pet)
    fair,at,conf,qty=tonumber(fair),tonumber(at),tonumber(conf),tonumber(qty)
    local key=self:Key(id,suffix,level,pet)
    if not key or not validWhole(self,fair,1,1e12) or not validWhole(self,at,t-7*86400,t)
      or not validWhole(self,conf,0,100) or not validWhole(self,qty,0,1e9)
      or unique[tostring(key)] then return false,'Invalid or duplicate observation at line '..i end
    unique[tostring(key)]=true
    local floor,reliable=tonumber(fields[9]),tonumber(fields[10])
    if magic=='VMMX2' and (not validWhole(self,floor,1,1e12) or not validWhole(self,reliable,0,1)) then return false,'Invalid asking price' end
    staged[#staged+1]={key=key,id=id,suffix=suffix,level=level,pet=pet,fair=fair,at=at,confidence=conf,quantity=qty,floor=floor,reliable=reliable==1}
  end
  local book=self.db.sharedPrices
  local updated=0
  for _,s in ipairs(staged) do
    local previous=book[s.key]
    if s.floor then
      self:MergeAsk(s);if book[s.key]==s then updated=updated+1 end
    elseif not previous or (not previous.floor and (tonumber(previous.at) or 0)<s.at) then
      book[s.key]=s;updated=updated+1
    end
  end
  -- Bound imported price-only cache, without modifying trusted market history.
  local all={}
  for key,s in pairs(book) do
    if type(s)=='table' and not s.floor then all[#all+1]={key=key,at=tonumber(s.at) or 0} end
  end
  table.sort(all,function(a,b)return a.at>b.at end)
  for i=201,#all do book[all[i].key]=nil end
  if self.view=='browse' then self:BuildBrowseRows(self.db.settings.filter or '') end
  self:RefreshUI()
  return true,'Imported '..updated..' newer advisory prices; no history or trade eligibility changed'
end


-- VMMW1 shopping-list transfer: independent of prices and execution state.
-- This format is small enough for manual clipboard exchange between WoW accounts.
function M:ExportShoppingTransfer()
  local realm,faction=self.economyID:match('^(.-)|([^|]+)$')
  if not realm or realm:find('[\t\r\n]') or faction:find('[\t\r\n]') then return nil,'Invalid economy' end
  local rows={}
  for key,entry in pairs(self:ListBook(self.activeList) or {}) do
    if type(entry)=='table' then
      local market=self.db.market[key]
      local id,suffix,level,pet
      if market then
        id,suffix,level,pet=market.itemID,market.itemSuffix or 0,market.itemLevel or 0,market.battlePetSpeciesID or 0
      else
        local value=tostring(key)
        id=tonumber(value:match('^(%d+)'))
        suffix=tonumber(value:match(':s(-?%d+)')) or 0
        level=tonumber(value:match(':l(%d+)')) or 0
        pet=tonumber(value:match(':p(%d+)')) or 0
      end
      local target=entry.target
      if self:Key(id,suffix,level,pet)==key
        and (target==nil or (self:Finite(target,1,1e12) and target%1==0)) then
        local name=tostring(entry.name or market and market.name or ('Item '..id))
          :gsub('[\t\r\n]',' '):sub(1,100)
        rows[#rows+1]={key=tostring(key),line=table.concat({id,suffix,level,pet,target or 0,name},'\t')}
      end
    end
  end
  table.sort(rows,function(a,b) return a.key<b.key end)
  if #rows>200 then return nil,'Too many shopping entries (limit 200)' end
  local output={'VMMW2\t'..realm..'\t'..faction..'\t'..time()..'\t'..#rows..'\t'..self.activeList}
  for _,row in ipairs(rows) do output[#output+1]=row.line end
  return table.concat(output,'\n')
end
function M:ImportShoppingTransfer(raw)
  if self.persistenceBlocked then return false,'Database read-only' end
  if type(raw)~='string' or #raw>35000 then return false,'Invalid shopping transfer length' end
  raw=raw:gsub('\r\n','\n'):gsub('\n+$','')
  -- Auctionator list export ("Name^term^term"): imported as search terms.
  if not raw:find('^VMMW') and raw:find('^',1,true) and self.ImportAuctionatorLists then
    local ok,msg=self:ImportAuctionatorLists(raw);if ok then self:Print(msg) end;return ok,msg
  end
  local lines={}
  for line in (raw..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
  if #lines<1 or #lines>201 then return false,'Too many shopping rows' end
  local realm,faction=self.economyID:match('^(.-)|([^|]+)$')
  local header,list=lines[1]:match('^(VMMW2\t[^\t]+\t[^\t]+\t%d+\t%d+)\t([^\t]+)$')
  if list and (#list>24 or list:find('[%c|]')) then return false,'Invalid list name' end
  local magic,r,f,at,count=(header or lines[1]):match('^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$')
  at,count=tonumber(at),tonumber(count)
  if (magic~='VMMW1' and not (magic=='VMMW2' and list)) or r~=realm or f~=faction then return false,'Realm/faction or format mismatch' end
  if not validWhole(self,at,time()-30*86400,time()+300)
    or not validWhole(self,count,0,200) or count~=#lines-1 then return false,'Invalid shopping header' end
  local staged,seen={},{}
  for i=2,#lines do
    local id,suffix,level,pet,target,name=lines[i]:match('^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]*)$')
    id,suffix,level,pet,target=tonumber(id),tonumber(suffix),tonumber(level),tonumber(pet),tonumber(target)
    local key=self:Key(id,suffix,level,pet)
    if not key or not validWhole(self,target,0,1e12) or not name or #name>100 or name:find('[%c]')
      or seen[tostring(key)] then return false,'Invalid shopping row '..i end
    seen[tostring(key)]=true
    staged[#staged+1]={key=key,name=name~='' and name or ('Item '..id),target=target>0 and target or nil,id=id}
  end
  local book=self:ListBook(list or 'Shopping') or {}
  local existing=0
  for _ in pairs(book) do existing=existing+1 end
  local new=0
  for _,entry in ipairs(staged) do if not book[entry.key] then new=new+1 end end
  if existing+new>200 then return false,'Import would exceed 200 shopping entries' end
  local updated=0
  book=self:ListBook(list or 'Shopping',true);if not book then return false,'List limit reached' end
  for _,entry in ipairs(staged) do
    local previous=book[entry.key]
    -- Never overwrite locally edited targets. Incoming entries only fill gaps.
    if not previous then
      book[entry.key]={at=at,target=entry.target,name=entry.name,itemID=entry.id}
      self:PublishWatch(list or 'Shopping',entry.key,book[entry.key])
      updated=updated+1
    end
  end
  self:RefreshUI()
  return true,'Imported '..updated..' new shopping entries; existing targets preserved'
end
