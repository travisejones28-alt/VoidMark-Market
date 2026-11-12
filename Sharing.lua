local _,M=...
-- Latest-state journal: one pending revision per variant/list entry, not one
-- historical row per change. A receiver advances only after validating a page.
local PREFIX='VMMkt2'
-- 1.21 fast sync: extra prefixes ("lanes") each get their own client send
-- budget, the economy name becomes a 5-character hash, and numbers in rows
-- are packed (base-62, timestamps as offsets). Used only after the partner
-- says it understands it ("C" message); older partners keep the 1.x format.
local LANES={PREFIX,'VMMkt2b','VMMkt2c','VMMkt2d'}
local LANE_SET={};for _,l in ipairs(LANES) do LANE_SET[l]=true end
local B62='0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
local function b62(n)
 n=math.floor(n);if n<=0 then return '0' end
 local out='';while n>0 do local d=n%62;out=B62:sub(d+1,d+1)..out;n=(n-d)/62 end;return out
end
local B62V={};for i=1,62 do B62V[B62:sub(i,i)]=i-1 end
local function unb62(t)
 if type(t)~='string' or t=='' or #t>8 then return nil end
 local n=0;for i=1,#t do local v=B62V[t:sub(i,i)];if not v then return nil end;n=n*62+v end;return n
end
local function econHash(id)
 local h=5381;id=tostring(id):gsub('%s',''):lower()
 for i=1,#id do h=(h*33+id:byte(i))%916132832 end -- 62^5
 local t=b62(h);return ('0'):rep(5-#t)..t
end
local function packField(f,base)
 if f:sub(1,1)=='!' then return '!'..f end
 if f:match('^%d+$') and #f>=3 and tostring(tonumber(f))==f then
  local n=tonumber(f)
  if n>=1000000000 and n>=base then local t='!^'..b62(n-base);if #t<#f then return t end end
  local t='!'..b62(n);if #t<#f then return t end
 end
 return f
end
local function unpackField(f,base)
 if f:sub(1,2)=='!!' then return f:sub(2) end
 if f:sub(1,2)=='!^' then local n=unb62(f:sub(3));return n and tostring(base+n) or nil end
 if f:sub(1,1)=='!' then local n=unb62(f:sub(2));return n and tostring(n) or nil end
 return f
end
local function packRow(line,base)
 local out={};for v in (line..','):gmatch('([^,]*),') do out[#out+1]=packField(v,base) end;return table.concat(out,',')
end
local function unpackRow(line,base)
 local out={};for v in (line..','):gmatch('([^,]*),') do local u=unpackField(v,base);if not u then return nil end;out[#out+1]=u end
 return table.concat(out,',')
end
M.SyncPack={b62=b62,unb62=unb62,hash=econHash,pack=packRow,unpack=unpackRow,lanes=LANES}
local STAMP_EVERY=1800
local function secret(v) return issecretvalue and issecretvalue(v) end
local function unitCharacter(unit)
 -- Forever returns first name and surname separately. A surname is not a realm.
 if NameUtil and NameUtil.GetUnmodifiedUnitFullName and UnitNameUnmodified then
  local first,last=UnitNameUnmodified(unit)
  if secret(first) or secret(last) or not first then return end
  return NameUtil.GetFullNameWithoutRealm(first,last)
 end
 local first,second=UnitName(unit)
 if secret(first) or secret(second) or type(first)~='string' then return end
 -- Forever puts the surname in the slot other clients use for a realm.
 local realm=(GetRealmName and GetRealmName()) or ''
 if type(second)=='string' and second~='' and not first:find(' ',1,true)
  and second:gsub('%s',''):lower()~=tostring(realm):gsub('%s',''):lower() then return first..' '..second end
 return first
end
-- "First Surname" key for a character however the client writes it:
-- "Voidmark Bank", "Voidmark-Bank" or "Voidmark Bank-Realm".
local function realmKey() return tostring((GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ''):gsub('%s',''):lower() end
local function nameKey(name)
 if secret(name) or type(name)~='string' or name=='' then return end
 local s=name:lower();local realm=realmKey()
 local base,tail=s:match('^(.-)%-([^%-]+)$')
 if base and base~='' and tail:gsub('%s','')==realm then s=base end
 s=s:gsub('%-',' '):gsub('%s+',' '):match('^%s*(.-)%s*$')
 return s~='' and s or nil
end
M.SharingNameKey=nameKey
local function enc(s) return (tostring(s):gsub('[%%%c,;|/]',function(c)return ('%%%02X'):format(c:byte()) end)) end
local function dec(s) return (s:gsub('%%(%x%x)',function(x)return string.char(tonumber(x,16)) end)) end
local function fields(s,sep)
 local out={};for v in (s..sep):gmatch('([^'..sep..']*)'..sep) do out[#out+1]=v end;return out
end
local function whole(v,lo,hi) return M:Finite(v,lo,hi) and v%1==0 end
local function validText(s,n) return type(s)=='string' and #s>0 and #s<=n and not s:find('[%c|]') end
function M:ParseKey(value)
 local k=tostring(value);local id,s,l,p=k:match('^(%d+):s(-?%d+):l(%d+):p(%d+)$')
 if not id then id,s=k:match('^(%d+):s(-?%d+)$') end
 id=id or k:match('^(%d+)$')
 local key=self:Key(id,s,l,p);if not key or tostring(key)~=k then return end
 return key,tonumber(id),tonumber(s) or 0,tonumber(l) or 0,tonumber(p) or 0
end
function M:ListBook(list,create)
 if not list or list=='Shopping' then return self.db.watchlist end
 if not validText(list,24) then return end
 local all=self.db.shoppingLists
 if not all[list] and create then
  local n=0;for _ in pairs(all) do n=n+1 end
  if n>=24 then return end
  all[list]={}
 end
 return all[list]
end
function M:InitializeSharing()
 local d=self.db
 d.shoppingLists=d.shoppingLists or {};d.shoppingEdits=d.shoppingEdits or {}
 d.shareJournal=d.shareJournal or {epoch=tostring(time())..'-'..math.random(1000,999999),seq=0,latest={},rows={}}
 d.shareBases=d.shareBases or {};d.shareReceived=d.shareReceived or {};self.shareRun={}
 self.activeList=d.activeList or 'Shopping'
 if d.syncAutoPairSeen==nil and not self.persistenceBlocked then
  local name=(unitCharacter('player') or ''):lower()
  local peer=name=='voidmark soulreaver' and 'Voidmark Bank' or name=='voidmark bank' and 'Voidmark Soulreaver'
  if peer then
   d.syncAutoPairSeen=true
   if not d.syncPeer then self:PairPeer(peer) end
  end
 end
end
function M:SetList(name)
 name=tostring(name or ''):match('^%s*(.-)%s*$')
 if self.persistenceBlocked or not self:ListBook(name,true) then return false,'Use a list name of 1-24 characters (24 lists maximum)' end
 self.activeList=name;self.db.activeList=name;self.selectedRow=nil;self.page=1;self:RefreshUI();return true
end
function M:Journal(key,line)
 if self.persistenceBlocked then return end
 local j=self.db.shareJournal;local old=j.latest[key]
 if old and j.rows[old]==line then return end
 if old then j.rows[old]=nil end
 j.seq=j.seq+1;j.rows[j.seq]=line;j.latest[key]=j.seq
end
-- catchUp publishes an older trusted observation (e.g. scanned before pairing)
-- so the partner can still use it; its timestamp keeps it labelled stale and
-- it never replaces a newer observation on the receiving side.
function M:PublishPrice(m,catchUp)
 if not m or not self:ParseKey(m.marketKey) or m.cacheUntrusted or m.analysisIncomplete or type(m.latest)~='table' then return end
 if not self:MarketFresh(m) and not (catchUp and self:Finite(m.lastSeen,time()-self.db.settings.historyDays*86400,time()+60)) then return end
 local floor=m.latest.floor
 if self:Finite(floor,0.000001,1e12) then floor=math.ceil(floor) end
 if not whole(floor,1,1e12) or not whole(m.lastSeen,1,time()+60) then return end
 local fair=self:CanEstimateResale(m) and m.fairValue or 0
 local j=self.db.shareJournal;local index='P'..m.marketKey
 local old=j.latest[index] and j.rows[j.latest[index]]
 local a,b,c,d
 if old then a,b,c,d=old:match('^P,[^,]+,(%d+),(%d+),(%d+),(%d+)$') end
 -- A saved legacy entry without confidence is published in the new format.
 local confidence=whole(m.confidenceScore,0,100) and m.confidenceScore or 0
 if tonumber(b)==floor and tonumber(c)==fair and tonumber(d)==confidence then
  local stampRow=j.latest['U'..m.marketKey] and j.rows[j.latest['U'..m.marketKey]]
  local stamped=tonumber(stampRow and stampRow:match(',(%d+)$')) or tonumber(a)
  -- Freshness-only rows were most of the traffic after each scan; an unchanged
  -- price is re-stamped at most every 30 minutes (well inside the 2h window).
  if m.lastSeen>tonumber(a) and m.lastSeen-stamped>=STAMP_EVERY then self:Journal('U'..m.marketKey,table.concat({'U',m.marketKey,a,m.lastSeen},',')) end
 else
  local u='U'..m.marketKey;if j.latest[u] then j.rows[j.latest[u]]=nil;j.latest[u]=nil end
  self:Journal(index,table.concat({'P',m.marketKey,m.lastSeen,floor,fair,confidence},','))
 end
end
-- 1.9.3: a live search on this account also updates the partner. Sent as an
-- ordinary price row with no estimate (fair 0), so the partner keeps its
-- existing history estimate and its age. Unchanged floors repeat at most
-- every 30 minutes, the same as scan stamps.
function M:PublishLiveFloor(key,floor,at)
 if not self.db.syncPeer or self.persistenceBlocked or self.db.settings.shareLivePrices==false then return end
 if not self:ParseKey(key) or not whole(floor,1,1e12) or not whole(at,1,time()+60) then return end
 local j=self.db.shareJournal;local index='P'..key
 local old=j.latest[index] and j.rows[j.latest[index]]
 local oldAt,oldFloor
 if old then oldAt,oldFloor=old:match('^P,[^,]+,(%d+),(%d+),')  end
 oldAt,oldFloor=tonumber(oldAt),tonumber(oldFloor)
 if oldAt and oldAt>=at then return end
 local u=j.latest['U'..key] and j.rows[j.latest['U'..key]]
 local stamped=tonumber(u and u:match(',(%d+)$')) or oldAt
 if oldFloor==floor and stamped and at-stamped<STAMP_EVERY then return end
 if u then j.rows[j.latest['U'..key]]=nil;j.latest['U'..key]=nil end
 self:Journal(index,table.concat({'P',key,at,floor,0,0},','))
end
local function listKey(list,key) return enc(list)..'/'..key end
function M:PublishWatch(list,key,entry)
 if not self:ParseKey(key) then return end
 local index=listKey(list,key);local old=self.db.shoppingEdits[index]
 local at=math.max(entry and entry.at or time(),old and old.at+1 or 0)
 local author=(unitCharacter('player') or ''):lower()
 local price=entry and (entry.target or 0) or -1
 local line=table.concat({'W',enc(list),key,at,price,enc(author)},',')
 self.db.shoppingEdits[index]={at=at,author=author}
 self:Journal('W'..index,line)
end
local function decode(self,line)
 local f=fields(line,',')
 if f[1]=='P' and (#f==5 or #f==6) then
  local key,id,s,l,p=self:ParseKey(f[2]);local at,floor,fair=tonumber(f[3]),tonumber(f[4]),tonumber(f[5])
  local confidence=#f==6 and tonumber(f[6]) or nil
  if key and whole(at,1,time()+60) and whole(floor,1,1e12) and whole(fair,0,1e12)
    and (confidence==nil and #f==5 or whole(confidence,0,100)) then
   return {kind='P',key=key,id=id,suffix=s,level=l,pet=p,at=at,floor=floor,fair=fair>0 and fair or nil,reliable=fair>0,confidence=confidence}
  end
 elseif f[1]=='U' and #f==4 then
  local key=self:ParseKey(f[2]);local base,at=tonumber(f[3]),tonumber(f[4])
  if key and whole(base,1,time()+60) and whole(at,base,time()+60) then return {kind='U',key=key,base=base,at=at} end
 elseif f[1]=='W' and #f==6 then
  local list=dec(f[2]);local key,id=self:ParseKey(f[3]);local at,target=tonumber(f[4]),tonumber(f[5]);local author=dec(f[6])
  if key and validText(list,24) and validText(author,48) and whole(at,1,time()+300) and whole(target,-1,1e12) then
   return {kind='W',key=key,id=id,list=list,at=at,target=target,author=author}
  end
 end
end
function M:MergeAsk(p)
 local prev=self.db.sharedPrices[p.key]
 -- Compare the ask and the historical estimate independently. A new scan
 -- with a valid floor but no established model does not erase good history.
 local histAt=prev and (prev.histAt or (prev.reliable and prev.at))
 local histFair=prev and (prev.histFair or (prev.reliable and prev.fair))
 if p.reliable and p.fair and (not histAt or p.at>histAt) then histAt,histFair=p.at,p.fair end
 if prev and prev.floor and ((prev.at or 0)>p.at or prev.at==p.at and (prev.reliable or not p.reliable)) then
  prev.histAt,prev.histFair=histAt,histFair;return
 end
 p.histAt,p.histFair=histAt,histFair;self.db.sharedPrices[p.key]=p
end
local function apply(self,p)
 if p.kind=='P' then
  p.origin=self.db.syncPeer;p.base=p.at;self.db.shareBases[p.key]=p;self:MergeAsk(p);return true
 end
 if p.kind=='U' then
  local prev=self.db.sharedPrices[p.key]
  if prev and prev.origin==self.db.syncPeer and prev.base==p.base and p.at>prev.at then prev.at=p.at;if prev.reliable then prev.histAt=p.at end
  elseif prev and prev.at>=p.at then return true
  else
   -- An offline import can be newer than the original base. Its different
   -- price must never be restamped; resolve from the sender's full base.
   local base=self.db.shareBases[p.key]
   if base and base.origin==self.db.syncPeer and base.base==p.base then
    local copy={};for k,v in pairs(base) do copy[k]=v end;copy.at=p.at;self:MergeAsk(copy)
   end
  end
  return true
 end
 local index=listKey(p.list,p.key);local old=self.db.shoppingEdits[index]
 local book=self:ListBook(p.list,true);if not book then return false end
 local existing=book[p.key]
 if old and (old.at>p.at or old.at==p.at and old.author>=p.author) or
  (not old and existing and (existing.at or 0)>=p.at) then return true end
 if p.target>=0 and not existing then local n=0;for _ in pairs(book) do n=n+1 end;if n>=200 then return false end end
 self.db.shoppingEdits[index]={at=p.at,author=p.author}
 if p.target<0 then book[p.key]=nil else
  local m=self.db.market[p.key]
  local name=m and m.name or existing and existing.name or (GetItemInfo and GetItemInfo(p.id)) or 'Item '..p.id
  book[p.key]={at=p.at,target=p.target>0 and p.target or nil,name=name,itemID=p.id}
 end
 return true
end
local function fullAddress(name)
 if secret(name) then return end
 if not validText(name,80) then return end
 local character,realm=name:match('^(.-)%-(.+)$')
 character=(character or name):match('^%s*(.-)%s*$'):gsub(' +',' ')
 realm=realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
 if character=='' or not realm or realm=='' then return end
 return character..'-'..realm:gsub('%s','')
end
local function canonical(name)
 local address=fullAddress(name)
 return address and address:lower()
end
function M:PairPeer(name)
 if self.persistenceBlocked then return 'Database read-only' end
 if type(name)=='string' then name=name:match('^%s*(.-)%s*$') end
 if name=='' or (name and name:lower()=='off') then self.db.syncAutoPairSeen=true;self.db.syncPeer=nil;self.db.syncAddress=nil;self.shareRun={};self:RefreshUI();return 'Automatic sharing off' end
 if not name then return self:SharingStatus() end
 do local base,tail=name:match('^(.-)%-([^%-]+)$')
  -- Forever names always have a surname, so a single "First-Surname" is never a realm.
  if base and not base:find(' ',1,true) and tail:gsub('%s',''):lower()~=realmKey() then name=base..' '..tail end end
 local peer=canonical(name)
 if not peer or peer==canonical(unitCharacter('player')) then return 'Enter the other character name (First Surname)' end
 local realm=GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName()
 if peer:match('%-(.+)$')~=realm:gsub('%s',''):lower() then return 'Peer must be on the same realm' end
 if self.db.syncPeer~=peer then
  self.db.syncLastSentAt=nil;self.db.syncLastReceivedAt=nil;self.db.syncLastReceivedCompleteAt=nil
 end
 self.db.syncAddress=fullAddress(name)
 self.db.syncPeer=peer;self.db.shareJournal.seeded=nil;self.shareRun={};self:StartSharing();self:RefreshUI()
 return 'Peer set to '..peer..'. This is NOT connected yet. Use /vmm peer to check reply status.'
end
function M:SharingStatus()
 local peer=self.db.syncPeer
 if not peer then return 'Not paired. Pair each character with the other.' end
 local r=self.shareRun or {}
 local detail=r.lastChannel and (' via '..r.lastChannel) or ''
 if r.lastContact then detail=detail..' | last reply '..math.floor(GetTime()-r.lastContact)..'s ago' end
 return peer..' | '..(r.status or 'Waiting for partner reply')..detail
end
function M:QueueScanSharing(at)
 if not self.db.syncPeer or self.persistenceBlocked then return end
 local d=self.db;local keys=self.marketIndex;local i=1
 self:AddJob('share-scan',function(start)
  while true do
   local key=keys[i];if not key then return true end;i=i+1
   local m=d.market[key];if m and m.lastSeen==at then self:PublishPrice(m) end
   if debugprofilestop()-start>=3 then break end
  end
 end,function() self.shareRun.infoPending=true;self.shareRun.next=0 end)
end
-- Restrict the filter to the exact character specified by /vmm peer.
-- Filtering unrelated Blizzard system notices would hide useful errors.
function M:HandlePeerOfflineNotice(message)
 if type(message)~='string' or not self.db or not self.db.syncPeer then return false end
 local address=self.db.syncAddress or self.db.syncPeer
 local short=address:match('^([^-]+)')
 if not short then return false end
 local candidate=message:lower()
 local template=ERR_CHAT_PLAYER_NOT_FOUND or "No player named '%s' is currently playing."
 local match=false
 for _,name in ipairs({short,address,(short:gsub(' ','-',1))}) do
  local ok,expected=pcall(string.format,template,name)
  if ok and type(expected)=='string' and candidate==expected:lower() then match=true;break end
 end
 if not match then return false end
 local r=self.shareRun or {}
 self.shareRun=r
 r.offlineUntil=GetTime()+30 -- try again in 30s (VoidLink-style: the bank keeps knocking)
 r.cursor=nil;r.reply=nil;r.lastContact=nil
 r.hello=nil;r.retry=nil;r.skipped=nil;r.sentHi=nil;r.pages=nil
 r.status='Partner offline; quietly checking again in 1m'
 self:RefreshUI()
 return true
end
function M:StartSharing()
 local api=C_ChatInfo;self.shareRun=self.shareRun or {}
 if not self.offlineFilterHooked and ChatFrame_AddMessageEventFilter then
  ChatFrame_AddMessageEventFilter('CHAT_MSG_SYSTEM',function(_,event,msg)
   if M:HandlePeerOfflineNotice(msg) then return true end
   return false
  end)
  self.offlineFilterHooked=true
 end
 if self.persistenceBlocked or not self.db.syncPeer then return end
 if not api or not api.RegisterAddonMessagePrefix or not api.SendAddonMessage then
  self.shareRun.status='Addon messaging unavailable on this client';return
 end
 if not self.shareRegistered then
  -- Some Forever/Classic builds wrap the API and put the enum in the LAST
  -- return value. Never treat nil as successful registration.
  local ok,v=pcall(function() return select(-1,api.RegisterAddonMessagePrefix(PREFIX)) end)
  local success=Enum and Enum.RegisterAddonMessagePrefixResult and Enum.RegisterAddonMessagePrefixResult.Success or 0
  local duplicate=Enum and Enum.RegisterAddonMessagePrefixResult and Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix or 1
  self.shareRegistered=ok and (v==true or v==success or v==duplicate)
  if not self.shareRegistered and api.IsAddonMessagePrefixRegistered then
   local verified,registered=pcall(api.IsAddonMessagePrefixRegistered,PREFIX)
   self.shareRegistered=verified and registered==true
  end
  if not self.shareRegistered then self.shareRun.status='Addon-message registration failed (result '..tostring(v)..')' end
 end
 if self.shareRegistered and not self.shareLanes then
  local lanes={PREFIX}
  for i=2,#LANES do
   local ok,v=pcall(function() return select(-1,api.RegisterAddonMessagePrefix(LANES[i])) end)
   local success=Enum and Enum.RegisterAddonMessagePrefixResult and Enum.RegisterAddonMessagePrefixResult.Success or 0
   local duplicate=Enum and Enum.RegisterAddonMessagePrefixResult and Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix or 1
   if ok and (v==true or v==success or v==duplicate) then lanes[#lanes+1]=LANES[i] end
  end
  self.shareLanes=lanes
 end
 local d=self.db;local j=d.shareJournal
 -- 1.7: re-run seeding once so trusted prices observed before pairing (or
 -- older than the freshness window) are offered to the partner.
 if j.catchUpSeed~=2 then j.seeded=nil;j.catchUpSeed=2 end
 if not j.seeded then
  local cursor;self:AddJob('share-seed',function(start)
   for _=1,32 do
    local k,m=next(d.market,cursor);cursor=k
    if not k then
     for key,entry in pairs(d.watchlist) do if not d.shoppingEdits[listKey('Shopping',key)] then self:PublishWatch('Shopping',key,entry) end end
     j.seeded=true;return true
    end
    if type(m)=='table' and (tonumber(m.lastSeen) or 0)<=(d.lastDepthSnapshotAt or 0) then self:PublishPrice(m,true) end;if debugprofilestop()-start>=3 then return false end
   end
  end)
 end
end
local function channel(self)
 if GetNumGroupMembers and UnitFullName then
 local raid=IsInRaid and IsInRaid()
 for i=1,GetNumGroupMembers() do
  local n,r=UnitFullName((raid and 'raid' or 'party')..i)
  local identity
  if NameUtil and NameUtil.GetUnmodifiedUnitFullName then
   identity=unitCharacter((raid and 'raid' or 'party')..i)
  elseif not secret(n) and not secret(r) and n then identity=r and r~='' and n..'-'..r or n end
  if nameKey(identity) and nameKey(identity)==nameKey(self.db.syncPeer) then
   if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return 'INSTANCE_CHAT' end
   return raid and 'RAID' or 'PARTY'
  end
 end
 end
 return 'WHISPER'
end
local function send(self,ch,body,lane,short)
 local msg=(short and ('#'..econHash(self.economyID)) or self.economyID)..'\t'..body
 if #msg>240 then return false end
 local target
 if ch=='WHISPER' then
  local address=self.db.syncAddress or self.db.syncPeer
  local name=address:match('^([^-]+)')
  target=canonical(name)==self.db.syncPeer and name or address
  -- Until the partner answers, probes alternate "First Surname" and "First-Surname".
  if self.shareRun and self.shareRun.hyphenTarget then target=target:gsub(' ','-',1) end
 end
 -- The legacy compatibility wrapper can return (nil, enum). Read the
 -- final return value, and do not mistake a nil/false result for success.
 local ok,r=pcall(function() return select(-1,C_ChatInfo.SendAddonMessage(lane or PREFIX,msg,ch,target)) end)
 local success=Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
 local sent=ok and (r==true or r==success)
 self.shareRun.lastChannel=ch
 if not sent then
  self.shareRun.lastSendError=ok and tostring(r) or 'API error'
  self.shareRun.status='Send failed on '..ch..' (result '..self.shareRun.lastSendError..')'
 else self.shareRun.lastSendError=nil end
 return sent
end
local WINDOW,RATE,BURST=8,1200,3000 -- pages in flight, bytes/second, burst bytes
local function refill(r,now)
 local last=r.bucketAt or now;r.bucketAt=now
 r.bucket=math.min(BURST,(r.bucket or BURST)+(now-last)*RATE)
end
local function goBack(r) r.sentHi=r.cursor;r.pages={};r.skipped=nil end
local function inFlight(r) return r.pages and #r.pages or 0 end
local function dataReady(r,j,now)
 if r.cursor==nil or now<(r.throttleUntil or 0) then return false end
 if r.sentHi and r.sentHi>r.cursor and now>=(r.retry or 0) then return true end -- timed out: resend
 return math.max(r.cursor,r.sentHi or r.cursor)<j.seq and inFlight(r)<(r.window or WINDOW)
end
-- Fast mode (partner on 1.21+): packed pages, so more prices per message.
-- 1.22.4: ONE shared byte budget and the old 8-page window across all lanes.
-- 1.21 gave every lane its own budget (4x the traffic) and the server
-- disconnected the sending character for addon-message flooding. Lanes now
-- only route around a throttled prefix; they never add throughput.
local function fastPages(self,r,j,ch,now)
 local lanes=self.shareLanes or {PREFIX}
 local n=math.max(1,math.min(#lanes,tonumber(r.peerLanes) or 1))
 r.window=WINDOW;r.lu=r.lu or {}
 refill(r,now)
 local header='#'..econHash(self.economyID)
 local base=math.floor(time())-8000000;local base62=b62(base)
 for _=1,r.window do
  if not dataReady(r,j,now) then return end
  if r.sentHi and r.sentHi>r.cursor and now>=(r.retry or 0) then goBack(r) end
  local lo=math.max(r.cursor,r.sentHi or r.cursor);local hi=math.max(lo,r.skipped or lo);local rows={}
  local limit=math.min(j.seq,hi+500)
  local overhead=#header+1+#('E\t'..j.epoch..'\t'..lo..'\t'..limit..'\t'..base62..'\t')
  local used=0
  while hi<limit do
   local line=j.rows[hi+1]
   if line then line=packRow(line,base) end
   if line and #line+overhead>238 then hi=hi+1;r.oversized=(r.oversized or 0)+1;line=nil
   elseif line and used+(#rows>0 and 1 or 0)+#line+overhead>238 then break
   else hi=hi+1 end
   if line then used=used+(#rows>0 and 1 or 0)+#line;rows[#rows+1]=line end
  end
  if #rows==0 and hi<j.seq then r.skipped=hi;return end
  r.skipped=nil
  if hi<=lo then return end
  local body=table.concat({'E',j.epoch,lo,hi,base62,table.concat(rows,';')},'\t')
  local cost=#body+#header+1
  if (r.bucket or 0)<cost then return end
  local lane
  for k=1,n do local i=((r.laneNext or 0)+k-1)%n+1;if now>=(r.lu[i] or 0) then lane=i;break end end
  if not lane then return end
  r.laneNext=lane
  if send(self,ch,body,lanes[lane],true) then
   r.bucket=r.bucket-cost
   if not r.sentHi or r.sentHi<=r.cursor then r.retry=now+4 end
   r.sentHi=hi;r.pages=r.pages or {};r.pages[#r.pages+1]=hi
   r.status='Sending changes '..hi..' / '..j.seq..' (packed)'
  else
   -- The client refused (throttled): back off everything briefly, not just this lane.
   r.lu[lane]=now+3;r.throttleUntil=now+1.5;return
  end
 end
end
function M:PumpSharing()
 if self.db then self:AutomaticBankScan(GetTime()) end
 -- Keep the header's "Bank sync" line live on every view. It used to change
 -- only on a full redraw, so it could show "waiting for partner" long after
 -- the handshake succeeded (or "connected" after the partner left).
 if self.connectionLabel and self.window and self.window:IsShown() and GetTime()>=(self.syncLabelAt or 0) then
  self.syncLabelAt=GetTime()+1
  local text=self:SimpleSyncStatus()
  if text~=self.syncLabelText then self.syncLabelText=text;self.connectionLabel:SetText(text) end
 end
 if not self.db.syncPeer or self.persistenceBlocked or not self.shareRegistered then return end
 local r=self.shareRun;local now=GetTime()
 if self.view=='sync' and now>=(r.uiAt or 0) then r.uiAt=now+1;self:RefreshUI() end
 if now<(r.next or 0) then return end;r.next=now+0.15
 if (InCombatLockdown and InCombatLockdown()) or (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) then r.status='Paused by client restrictions';return end
 local j=self.db.shareJournal
 if not r.reply and not (r.infoPending and r.lastContact) and not (r.alerts and r.alerts[1] and r.lastContact) and r.hello and now<r.hello and not dataReady(r,j,now) then return end
 local ch=channel(self)
 if ch=='WHISPER' and r.offlineUntil and now<r.offlineUntil then return end
 if ch~='WHISPER' then r.offlineUntil=nil end
 if ch=='WHISPER' and r.lastContact and now-r.lastContact>65 then
  r.cursor=nil;r.reply=nil;r.lastContact=nil;r.hello=nil;r.sentHi=nil;r.pages=nil
 end
 if r.reply then
  if send(self,ch,r.reply) then r.reply=nil else r.next=now+5 end;return
 end
 -- Sale alerts go out ahead of price pages (dropped after 30 minutes undelivered).
 if r.alerts and r.alerts[1] then
  while r.alerts[1] and now-(r.alerts[1].at or now)>1800 do table.remove(r.alerts,1) end
  if r.alerts[1] and r.lastContact and self.EncodeSaleAlert then
   if send(self,ch,self:EncodeSaleAlert(j.epoch,r.alerts[1])) then table.remove(r.alerts,1) else r.next=now+2 end
   return
  end
 end
 if r.infoPending and r.lastContact then
  if send(self,ch,table.concat({'I',j.epoch,j.seq,self.db.lastDepthSnapshotAt or 0},'\t')) then r.infoPending=nil;r.capPending=true else r.next=now+5 end
  return
 end
 if r.capPending and r.lastContact then
  if send(self,ch,table.concat({'C',j.epoch,3,#(self.shareLanes or {PREFIX})},'\t')) then r.capPending=nil else r.next=now+5 end
  return
 end
 if not r.hello or now>=r.hello then
  r.helloHyphen=r.hyphenTarget or false
  local sent=send(self,ch,'H\t'..j.epoch)
  if sent then r.infoPending=true end
  local unconfirmed=ch=='WHISPER' and not r.lastContact
  if unconfirmed then r.hyphenTarget=not r.hyphenTarget end
  -- Unanswered probes back off to at most 30 s, so a partner who logs in
  -- later is found within half a minute. Once connected, a 20 s heartbeat.
  r.probeDelay=unconfirmed and math.min(30,(r.probeDelay or 10)*2) or 20
  r.hello=now+r.probeDelay
  if unconfirmed and sent then r.status='Whisper queued; waiting for partner reply (delivery unconfirmed)'
  elseif not sent then r.status='Message rejected on '..ch..' (result '..tostring(r.lastSendError)..'); retrying' end
  return
 end
 if r.peerV3 then return fastPages(self,r,j,ch,now) end
 r.window=nil
 refill(r,now)
 -- Pipelined pages: keep up to WINDOW pages in flight instead of waiting for
 -- each reply. The receiver applies pages strictly in order and replies with
 -- what it has; a lost page is resent from the confirmed point (go-back-N).
 for _=1,WINDOW do
  if not dataReady(r,j,now) then return end
  if r.sentHi and r.sentHi>r.cursor and now>=(r.retry or 0) then goBack(r) end -- no progress: resend
  local lo=math.max(r.cursor,r.sentHi or r.cursor);local hi=math.max(lo,r.skipped or lo);local rows={}
  local limit=math.min(j.seq,hi+500)
  while hi<limit do
   local line=j.rows[hi+1]
   local overhead=#self.economyID+#j.epoch+45
   if line and #line+overhead>235 then
    -- A revision that can never fit one message used to stall the whole
    -- transfer at this cursor. Skip it (the clipboard transfer still has it).
    hi=hi+1;r.oversized=(r.oversized or 0)+1;line=nil
   elseif line and #table.concat(rows,';')+#line+overhead>235 then break
   else hi=hi+1 end
   if line then rows[#rows+1]=line end
  end
  if #rows==0 and hi<j.seq then r.skipped=hi;return end
  r.skipped=nil
  if hi<=lo then return end
  local body=table.concat({'D',j.epoch,lo,hi,table.concat(rows,';')},'\t')
  if (r.bucket or 0)<#body+#self.economyID+1 then return end
  if send(self,ch,body) then
   r.bucket=r.bucket-(#body+#self.economyID+1)
   if not r.sentHi or r.sentHi<=r.cursor then r.retry=now+4 end -- progress deadline
   r.sentHi=hi;r.pages=r.pages or {};r.pages[#r.pages+1]=hi
   r.status='Sending changes '..hi..' / '..j.seq
  else
   r.throttleUntil=now+1.5;return -- client throttle: retry the same page shortly
  end
 end
end
function M:ReceiveSharing(prefix,msg,ch,sender)
 if secret(prefix) or secret(msg) or secret(ch) or secret(sender) then return end
 if not LANE_SET[prefix] or not self.db or self.persistenceBlocked or not self.db.syncPeer or nameKey(sender)~=nameKey(self.db.syncPeer) or
  (ch~='WHISPER' and ch~='PARTY' and ch~='RAID' and ch~='INSTANCE_CHAT') or type(msg)~='string' or #msg>240 then return end
 local f=fields(msg,'\t')
 local head=f[1] or ''
 if head:gsub('%s',''):lower()~=self.economyID:gsub('%s',''):lower() and head~='#'..econHash(self.economyID) then self.shareRun.status='Rejected peer: realm/faction mismatch';self:RefreshUI();return end
 if not f[3] or not f[3]:match('^%d+%-%d+$') then return end
 local r=self.shareRun;local j=self.db.shareJournal;local db=self.db.shareReceived
 local peer=self.db.syncPeer;local rx=db[peer]
 local function ack() r.reply=table.concat({'Q',rx.epoch,rx.seq},'\t');r.next=0 end
 if not r.lastContact and r.helloHyphen~=nil then r.hyphenTarget=r.helloHyphen end -- keep the form that got through
 if f[2]=='H' and #f==3 then
  if not r.lastContact then r.hello=nil end
  r.lastContact=GetTime();r.probeDelay=nil;r.offlineUntil=nil
  if not rx or rx.epoch~=f[3] then rx={epoch=f[3],seq=0};db[peer]=rx end
  ack();r.status='Partner connected'
 elseif f[2]=='I' and #f==5 and rx and f[3]==rx.epoch then
  local total,scan=tonumber(f[4]),tonumber(f[5])
  if not whole(total,rx.seq,1e12) or not whole(scan,0,time()+60) then return end
  local changed=rx.total~=total
  rx.total=total;rx.scanAt=scan>0 and scan or nil
  if changed and total>0 and rx.seq==total then self.db.syncLastReceivedCompleteAt=time() end
  self:RefreshUI()
 elseif f[2]=='Q' and f[3]==j.epoch and #f==4 then
  local n=tonumber(f[4]);if not whole(n,0,j.seq) then return end
  r.lastContact=GetTime();r.probeDelay=nil;r.offlineUntil=nil
  local progressed=n>(r.cursor or -1)
  if r.cursor~=n then r.skipped=nil end
  r.cursor=n
  if r.sentHi and r.sentHi>n then
   local keep={};for _,h in ipairs(r.pages or {}) do if h>n then keep[#keep+1]=h end end;r.pages=keep
   if progressed then r.retry=GetTime()+4
   elseif r.pages[1] and r.lastAck==n then goBack(r) end -- repeated reply: a page was lost
  else r.sentHi=n;r.pages={};r.retry=0 end
  if n==j.seq and r.lastAck~=n then self.db.syncLastSentAt=time() end
  r.lastAck=n;r.status=n==j.seq and 'Up to date' or 'Sending changes'
 elseif f[2]=='N' and #f==9 then
  if self.ReceiveSaleAlert then self:ReceiveSaleAlert(f,sender) end
 elseif f[2]=='C' and #f==5 then
  -- Partner understands fast pages (and how many lanes it listens on).
  local v,n=tonumber(f[4]),tonumber(f[5])
  if whole(v,1,99) and whole(n,1,#LANES) then r.peerV3=v>=3;r.peerLanes=n end
 elseif f[2]=='E' and #f==7 and rx and f[3]==rx.epoch then
  local lo,hi,base=tonumber(f[4]),tonumber(f[5]),unb62(f[6])
  if not whole(lo,0,1e12) or not whole(hi,lo+1,1e12) or not base then return end
  if lo<rx.seq then ack();return end -- already have it
  local staged={}
  if f[7]~='' then for _,line in ipairs(fields(f[7],';')) do
   local raw=unpackRow(line,base);local p=raw and decode(self,raw);if not p then return end;staged[#staged+1]=p
  end end
  r.buf=r.buf or {}
  if lo>rx.seq then
   -- Lanes can deliver out of order: hold it until the gap arrives.
   local count=0;for _ in pairs(r.buf) do count=count+1 end
   if count<96 then r.buf[lo]={hi=hi,staged=staged} end
   return
  end
  local page={hi=hi,staged=staged}
  while page do
   for _,p in ipairs(page.staged) do if not apply(self,p) then r.status='Shopping list limit reached; transfer paused';self:RefreshUI();return end end
   r.buf[rx.seq]=nil;rx.seq=page.hi
   page=r.buf[rx.seq]
  end
  for k in pairs(r.buf) do if k<rx.seq then r.buf[k]=nil end end
  r.lastContact=GetTime();r.offlineUntil=nil;self.db.syncLastReceivedAt=time();ack()
  if rx.total and rx.seq>=rx.total then self.db.syncLastReceivedCompleteAt=time() end
  if self.view=='browse' then self.browseNamesDirty=self.browseNamesDirty or GetTime()+1 end
  r.status='Received through change '..rx.seq..' (fast)';self:RefreshUI()
 elseif f[2]=='D' and #f==6 and rx and f[3]==rx.epoch then
  local lo,hi=tonumber(f[4]),tonumber(f[5])
  if not whole(lo,0,1e12) or not whole(hi,lo+1,1e12) then return end
  if lo~=rx.seq then ack();return end
  local staged={}
  if f[6]~='' then for _,line in ipairs(fields(f[6],';')) do
   local p=decode(self,line);if not p then return end;staged[#staged+1]=p
  end end
  for _,p in ipairs(staged) do if not apply(self,p) then r.status='Shopping list limit reached; transfer paused';self:RefreshUI();return end end
  r.lastContact=GetTime();r.offlineUntil=nil;rx.seq=hi;self.db.syncLastReceivedAt=time();ack()
  if rx.total and hi>=rx.total then self.db.syncLastReceivedCompleteAt=time() end
  if self.view=='browse' then self.browseNamesDirty=self.browseNamesDirty or GetTime()+1 end
  r.status='Received through change '..hi;self:RefreshUI()
 end
end
M:RegisterHandler('CHAT_MSG_ADDON',function(self,_,...) self:ReceiveSharing(...) end)
M:RegisterHandler('GROUP_ROSTER_UPDATE',function(self) if self.shareRun then self.shareRun.hello=nil end end)
-- Probe right away after loading screens and when a friend comes online.
M:RegisterHandler('PLAYER_ENTERING_WORLD',function(self) if self.shareRun and not self.shareRun.lastContact then self.shareRun.hello=nil;self.shareRun.offlineUntil=nil end end)
M:RegisterHandler('FRIENDLIST_UPDATE',function(self)
 local r=self.shareRun;local now=GetTime()
 if r and not r.lastContact and now>=(r.friendProbeAt or 0) then r.friendProbeAt=now+15;r.hello=nil;r.offlineUntil=nil end
end)
-- Backup detection when a chat-frame filter is unavailable on the client.
M:RegisterHandler('CHAT_MSG_SYSTEM',function(self,_,msg) self:HandlePeerOfflineNotice(msg) end)

function M:AutomaticBankScan(now)
 if now<(self.autoScanCheck or 0) then return end
 self.autoScanCheck=now+5
 if self.persistenceBlocked or self.db.settings.autoBankScan==false or
  (unitCharacter('player') or ''):lower()~='voidmark bank' or not self:CanUseAuctionHouse() or
  self.scanState.running or self:GetSecondsUntilFreshScanAllowed()>0 or
  (InCombatLockdown and InCombatLockdown()) or now<(self.autoScanNext or 0) then return end
 if not C_AuctionHouse or type(C_AuctionHouse.ReplicateItems)~='function' then return end
 self.autoScanNext=now+300
 self:RequestFreshScan()
end
function M:ReconnectSharing(force)
 if self.persistenceBlocked then return end
 -- Re-publish any locally available prices if a previous journal missed them.
 self.db.shareJournal.seeded=nil
 self.shareRun={};self.shareRegistered=nil
 if force then
  self.db.shareJournal.epoch=tostring(time())..'-'..math.random(1000,999999)
 end
 self:StartSharing();self:RefreshUI()
end
function M:SyncTime(at)
 return at and date('%Y-%m-%d %H:%M:%S',at) or 'Never'
end
function M:SyncReport()
 local r=self.shareRun or {};local j=self.db.shareJournal
 -- Count large caches in frame-budgeted slices only while this view is open.
 if not self.jobs['sync-count'] and GetTime()>=(r.countAt or 0) then
  local cursor;local count,newest=0,nil
  self:AddJob('sync-count',function(start)
   for _=1,80 do
    local k,p=next(self.db.sharedPrices,cursor);cursor=k
    if not k then r.priceCount=count;r.newestPrice=newest;r.countAt=GetTime()+10;self:RefreshUI();return true end
    if p.floor then count=count+1;newest=math.max(newest or 0,p.at or 0) end
    if debugprofilestop()-start>=2 then return false end
   end
  end)
 end
 local rx=self.db.shareReceived[self.db.syncPeer] or {}
 local diag=self.db.fullScanDiagnostic or {}
 return table.concat({
  'Voidmark Soulreaver <-> Voidmark Bank',self:SharingStatus(),
  'Economy (must match): '..self.economyID,
  'Last local scan: '..self:SyncTime(self.db.lastDepthSnapshotAt),
  'Last peer scan: '..self:SyncTime(rx.scanAt),
  'Newest received observation: '..self:SyncTime(r.newestPrice),
  'Last received page: '..self:SyncTime(self.db.syncLastReceivedAt),
  'Last complete receive: '..self:SyncTime(self.db.syncLastReceivedCompleteAt),
  'Last fully acknowledged send: '..self:SyncTime(self.db.syncLastSentAt),
  'Received prices: '..tostring(r.priceCount or 'Counting')..' | outbound revisions: '..tostring(r.cursor or 0)..' / '..j.seq,
  'Inbound revisions: '..tostring(rx.seq or 0)..' / '..tostring(rx.total or 'Awaiting peer metadata'),
  'Sync mode: '..(r.peerV3 and 'packed (more prices per message, same safe send rate)' or 'standard (partner not on 1.21 yet)'),
  'Scan: '..tostring(self.scanState.status)..' | progress: '..tostring(self.scanState.progress or 0),
  'Diagnostics: '..tostring(r.lastSendError or diag.error or 'No recorded error'),
  '', 'Bank scans automatically while its Auction House is open and cooldown permits.',
  'Both accounts must be online with reciprocal pairing. No group required.',
  'Whisper restrictions can block delivery; queued messages do not prove connection.',
  'Synced prices are observations, never live quotes or trade authorization.'},'\n')
end
