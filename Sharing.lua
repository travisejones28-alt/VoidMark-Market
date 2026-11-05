local _,M=...
-- Latest-state journal: one pending revision per variant/list entry, not one
-- historical row per change. A receiver advances only after validating a page.
local PREFIX='VMMkt2'
local function secret(v) return issecretvalue and issecretvalue(v) end
local function unitCharacter(unit)
 -- Forever returns first name and surname separately. A surname is not a realm.
 if NameUtil and NameUtil.GetUnmodifiedUnitFullName and UnitNameUnmodified then
  local first,last=UnitNameUnmodified(unit)
  if secret(first) or secret(last) or not first then return end
  return NameUtil.GetFullNameWithoutRealm(first,last)
 end
 local first=UnitName(unit)
 if not secret(first) then return first end
end
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
function M:PublishPrice(m)
 if not m or not self:ParseKey(m.marketKey) or not self:MarketFresh(m) or m.cacheUntrusted or m.analysisIncomplete or not m.latest then return end
 local floor=m.latest.floor
 if not whole(floor,1,1e12) or not whole(m.lastSeen,1,time()+60) then return end
 local fair=self:CanEstimateResale(m) and m.fairValue or 0
 local j=self.db.shareJournal;local index='P'..m.marketKey
 local old=j.latest[index] and j.rows[j.latest[index]]
 local a,b,c
 if old then a,b,c=old:match('^P,[^,]+,(%d+),(%d+),(%d+)$') end
 if tonumber(b)==floor and tonumber(c)==fair then
  if m.lastSeen>tonumber(a) then self:Journal('U'..m.marketKey,table.concat({'U',m.marketKey,a,m.lastSeen},',')) end
 else
  local u='U'..m.marketKey;if j.latest[u] then j.rows[j.latest[u]]=nil;j.latest[u]=nil end
  self:Journal(index,table.concat({'P',m.marketKey,m.lastSeen,floor,fair},','))
 end
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
 if f[1]=='P' and #f==5 then
  local key,id,s,l,p=self:ParseKey(f[2]);local at,floor,fair=tonumber(f[3]),tonumber(f[4]),tonumber(f[5])
  if key and whole(at,1,time()+60) and whole(floor,1,1e12) and whole(fair,0,1e12) then
   return {kind='P',key=key,id=id,suffix=s,level=l,pet=p,at=at,floor=floor,fair=fair>0 and fair or nil,reliable=fair>0}
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
 if name=='' or (name and name:lower()=='off') then self.db.syncPeer=nil;self.db.syncAddress=nil;self.shareRun={};self:RefreshUI();return 'Automatic sharing off' end
 if not name then return self:SharingStatus() end
 local peer=canonical(name)
 if not peer or peer==canonical(unitCharacter('player')) then return 'Enter the other character name (First Surname)' end
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
  for _=1,40 do
   local key=keys[i];if not key then return true end;i=i+1
   local m=d.market[key];if m and m.lastSeen==at then self:PublishPrice(m) end
   if debugprofilestop()-start>=3 then break end
  end
 end)
end
function M:StartSharing()
 local api=C_ChatInfo;self.shareRun=self.shareRun or {}
 if self.persistenceBlocked or not self.db.syncPeer or not api or not api.RegisterAddonMessagePrefix or not api.SendAddonMessage then return end
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
 local d=self.db;local j=d.shareJournal
 if not j.seeded then
  local cursor;self:AddJob('share-seed',function(start)
   for _=1,32 do
    local k,m=next(d.market,cursor);cursor=k
    if not k then
     for key,entry in pairs(d.watchlist) do if not d.shoppingEdits[listKey('Shopping',key)] then self:PublishWatch('Shopping',key,entry) end end
     j.seeded=true;return true
    end
    if type(m)=='table' and (tonumber(m.lastSeen) or 0)<=(d.lastDepthSnapshotAt or 0) then self:PublishPrice(m) end;if debugprofilestop()-start>=3 then return false end
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
  if canonical(identity)==self.db.syncPeer then
   if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return 'INSTANCE_CHAT' end
   return raid and 'RAID' or 'PARTY'
  end
 end
 end
 return 'WHISPER'
end
local function send(self,ch,body)
 local msg=self.economyID..'\t'..body
 if #msg>240 then return false end
 local target
 if ch=='WHISPER' then
  local address=self.db.syncAddress or self.db.syncPeer
  local name=address:match('^([^-]+)')
  target=canonical(name)==self.db.syncPeer and name or address
 end
 -- The legacy compatibility wrapper can return (nil, enum). Read the
 -- final return value, and do not mistake a nil/false result for success.
 local ok,r=pcall(function() return select(-1,C_ChatInfo.SendAddonMessage(PREFIX,msg,ch,target)) end)
 local success=Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
 local sent=ok and (r==true or r==success)
 self.shareRun.lastChannel=ch
 if not sent then
  self.shareRun.lastSendError=ok and tostring(r) or 'API error'
  self.shareRun.status='Send failed on '..ch..' (result '..self.shareRun.lastSendError..')'
 else self.shareRun.lastSendError=nil end
 return sent
end
function M:PumpSharing()
 if not self.db.syncPeer or self.persistenceBlocked or not self.shareRegistered then return end
 local r=self.shareRun;local now=GetTime()
 if now<(r.next or 0) then return end;r.next=now+0.5
 if (InCombatLockdown and InCombatLockdown()) or (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) then r.status='Paused by client restrictions';return end
 local j=self.db.shareJournal
 if not r.reply and r.hello and now<r.hello and (not r.cursor or r.cursor>=j.seq or now<(r.retry or 0)) then return end
 local ch=channel(self)
 if ch=='WHISPER' and r.lastContact and now-r.lastContact>65 then
  r.cursor=nil;r.reply=nil;r.lastContact=nil;r.hello=nil
 end
 if r.reply then
  if send(self,ch,r.reply) then r.reply=nil else r.next=now+5 end;return
 end
 if not r.hello or now>=r.hello then
  local sent=send(self,ch,'H\t'..j.epoch)
  local unconfirmed=ch=='WHISPER' and not r.lastContact
  r.probeDelay=unconfirmed and math.min(300,(r.probeDelay or 10)*2) or 20
  r.hello=now+r.probeDelay
  if unconfirmed and sent then r.status='Whisper queued; waiting for partner reply (delivery unconfirmed)'
  elseif not sent then r.status='Message rejected on '..ch..' (result '..tostring(r.lastSendError)..'); retrying' end
  return
 end
 if r.cursor==nil or r.cursor>=j.seq or now<(r.retry or 0) then return end
 local lo=r.cursor;local hi=math.max(lo,r.skipped or lo);local rows={}
 -- Skip superseded revisions without blocking the frame or padding the wire.
 local limit=math.min(j.seq,hi+500)
 while hi<limit do
  local line=j.rows[hi+1]
  if line and #table.concat(rows,';')+#line+#self.economyID+#j.epoch+45>235 then break end
  hi=hi+1;if line then rows[#rows+1]=line end
 end
 if #rows==0 and hi<j.seq then r.skipped=hi;return end
 r.skipped=nil
 if hi>lo then
  r.retry=now+4
  if send(self,ch,table.concat({'D',j.epoch,lo,hi,table.concat(rows,';')},'\t')) then r.status='Sending changes '..hi..' / '..j.seq end
 end
end
function M:ReceiveSharing(prefix,msg,ch,sender)
 if secret(prefix) or secret(msg) or secret(ch) or secret(sender) then return end
 if prefix~=PREFIX or not self.db or self.persistenceBlocked or not self.db.syncPeer or canonical(sender)~=self.db.syncPeer or
  (ch~='WHISPER' and ch~='PARTY' and ch~='RAID' and ch~='INSTANCE_CHAT') or type(msg)~='string' or #msg>240 then return end
 local f=fields(msg,'\t')
 if f[1]~=self.economyID or not f[3] or not f[3]:match('^%d+%-%d+$') then return end
 local r=self.shareRun;local j=self.db.shareJournal;local db=self.db.shareReceived
 local peer=self.db.syncPeer;local rx=db[peer]
 local function ack() r.reply=table.concat({'Q',rx.epoch,rx.seq},'\t') end
 if f[2]=='H' and #f==3 then
  if not r.lastContact then r.hello=nil end
  r.lastContact=GetTime();r.probeDelay=nil
  if not rx or rx.epoch~=f[3] then rx={epoch=f[3],seq=0};db[peer]=rx end
  ack();r.status='Partner connected'
 elseif f[2]=='Q' and f[3]==j.epoch and #f==4 then
  local n=tonumber(f[4]);if not whole(n,0,j.seq) then return end
  r.lastContact=GetTime();r.probeDelay=nil
  if r.cursor~=n then r.skipped=nil end;r.cursor=n;r.retry=0;r.status=n==j.seq and 'Up to date' or 'Sending changes'
 elseif f[2]=='D' and #f==6 and rx and f[3]==rx.epoch then
  local lo,hi=tonumber(f[4]),tonumber(f[5])
  if not whole(lo,0,1e12) or not whole(hi,lo+1,1e12) then return end
  if lo~=rx.seq then ack();return end
  local staged={}
  if f[6]~='' then for _,line in ipairs(fields(f[6],';')) do
   local p=decode(self,line);if not p then return end;staged[#staged+1]=p
  end end
  for _,p in ipairs(staged) do if not apply(self,p) then r.status='Shopping list limit reached; transfer paused';self:RefreshUI();return end end
  r.lastContact=GetTime();rx.seq=hi;ack();r.status='Received through change '..hi;self:RefreshUI()
 end
end
M:RegisterHandler('CHAT_MSG_ADDON',function(self,_,...) self:ReceiveSharing(...) end)
M:RegisterHandler('GROUP_ROSTER_UPDATE',function(self) if self.shareRun then self.shareRun.hello=nil end end)
