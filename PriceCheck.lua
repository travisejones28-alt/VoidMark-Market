local _,M=...
-- Price check replies (1.23.33): someone types "pricecheck [item]" (or "price
-- check", "pc [item]") in party/raid, guild or a whisper and Market answers in
-- the same place with the last scan's price.
-- Two clients (main + bank) or friends with Market may hear the same ask: each
-- waits a short random moment and stays quiet if someone already answered that
-- item there. A client with no price waits longer, so one with a price wins.
local PREFIX='VoidMark price:'
local CHANNELS={
 CHAT_MSG_PARTY={'PARTY','priceCheckParty'},CHAT_MSG_PARTY_LEADER={'PARTY','priceCheckParty'},
 CHAT_MSG_RAID={'RAID','priceCheckParty'},CHAT_MSG_RAID_LEADER={'RAID','priceCheckParty'},
 CHAT_MSG_GUILD={'GUILD','priceCheckGuild'},CHAT_MSG_OFFICER={'OFFICER','priceCheckGuild'},
 CHAT_MSG_WHISPER={'WHISPER','priceCheckWhisper'}}
M.priceCheck=M.priceCheck or {pending={},answered={},sent={}}
local PC=M.priceCheck
local REPEAT=30 -- same item in the same place answered at most once per 30s
local MAX_LINKS=3

local function now() return (GetTime and GetTime()) or time() end
-- Plain text money for chat (chat can't show coin icons): "12g 3s 40c".
function M:PlainCoins(v)
 v=tonumber(v);if not v or v<1 then return '0c' end
 v=math.floor(v);local g,s,c=math.floor(v/10000),math.floor(v/100)%100,v%100
 local out={}
 if g>0 then out[#out+1]=g..'g' end
 if s>0 then out[#out+1]=s..'s' end
 if c>0 or #out==0 then out[#out+1]=c..'c' end
 return table.concat(out,' ')
end
function M:IsPriceCheckAsk(msg)
 if type(msg)~='string' or msg:sub(1,#PREFIX)==PREFIX then return false end
 if not msg:find('|Hitem:',1,true) then return false end
 -- Link colours come as |cffRRGGBB or, on newer clients, |cnIQ1: (by quality).
 local plain=msg:gsub('|c[^|]*',''):gsub('|H.-|h(.-)|h','%1'):gsub('|r',''):lower()
 return plain:find('price%s*check')~=nil or plain:find('^%s*!?pc%s')~=nil or plain:find('^%s*!?pc%[')~=nil
end
local function links(msg)
 local out={}
 for link in msg:gmatch('|c[^|]*|Hitem:[^|]+|h%[.-%]|h|r') do
  out[#out+1]=link;if #out>=MAX_LINKS then break end
 end
 if #out==0 then
  for link in msg:gmatch('|Hitem:[^|]+|h%[.-%]|h') do out[#out+1]=link;if #out>=MAX_LINKS then break end end
 end
 return out
end
local function cap(t) if #t>255 then return t:sub(1,252)..'...' end return t end
local function secret(...)
 if not issecretvalue then return false end
 for i=1,select('#',...) do if issecretvalue((select(i,...))) then return true end end
 return false
end
local function itemID(link) return tonumber(tostring(link):match('item:(%d+)')) end
-- Reply text for one link, and whether we had a price at all.
-- link: an item link, or for a typed name the text to show ("[Bronze Bar]")
-- with key/name/id from the name lookup.
function M:PriceCheckReply(link,key,name,id)
 if not self.db then return nil end
 if not name then key=self:LinkIdentity(link);name=self:LinkName(link) end
 local p
 if key~=nil then
  local state,sf=self:VariantPrice(key,name,name)
  if state=='suffix' then p={floor=sf.floor,at=sf.at}
  elseif state=='key' then p=self:PriceObservation(key) end
 end
 local tp=(key==nil or self:VariantPrice(key,name,name)~='none') and self:TSMPrice(id or link)
 if not p or not self:Finite(p.floor,1,1e12) then
  if tp then return cap(PREFIX..' '..link..' '..self:PlainCoins(tp)..' (TSM)'),true end
  return PREFIX..' '..link..' no scan data',false
 end
 -- Ours is from an earlier day and TSM has one: TSM's is fresher.
 if tp and time()-p.at>=86400 then return cap(PREFIX..' '..link..' '..self:PlainCoins(tp)..' (TSM; our scan '..self:TooltipAgeText(p.at)..' old)'),true end
 local text=PREFIX..' '..link..' '..self:PlainCoins(p.floor)
 local scan=self.NewestFullScanAt and self:NewestFullScanAt()
 if scan and p.at<scan-300 and not p.unverified then
  text=text..' (none listed in last scan, last seen '..self:TooltipAgeText(p.at)..' ago)'
 else
  text=text..' (scanned '..self:TooltipAgeText(p.at)..' ago)'
 end
 if self:Finite(p.fair,1,1e12) and math.abs(p.fair-p.floor)>=p.floor*0.1 then
  text=text..', usually '..self:PlainCoins(p.fair)
 end
 return cap(text),true
end
-- Someone (us on another client, a friend) already answered this item here.
local function place(channel,target) return channel..'|'..(channel=='WHISPER' and tostring(target) or '') end
-- Answers are matched by item name, so a linked ask and a typed one are the same.
local function nameKey(text) local n=tostring(text):match('%[(.-)%]');return n and n:lower() end
function M:NotePriceCheckAnswer(channel,target,msg)
 if type(msg)~='string' or msg:sub(1,#PREFIX)~=PREFIX then return end
 local n=nameKey(msg);if not n then return end
 PC.answered[place(channel,target)..'|'..n]=now()
end
-- "price check bronze bar" / "pc bronze bar": the typed name, or nil.
function M:PriceCheckTypedName(msg)
 if type(msg)~='string' or msg:find('|H',1,true) then return nil end
 local l=msg:lower()
 local q=l:match('^%s*!?price%s*check%s*[:%-]?%s+(.+)$') or l:match('^%s*!?pc%s+(.+)$')
 if not q then return nil end
 q=q:gsub('[%?!%.]+%s*$',''):gsub('^%s+',''):gsub('%s+$',''):gsub('^%[(.-)%]$','%1')
 if #q<3 then return nil end
 return q
end
-- An item's name for typed lookups. A full scan can save items the game hadn't
-- loaded yet with no name ("" or "Item 2771"), so fall back to remembered
-- names, then the game's cache. Only already-loaded items are asked for, so a
-- lookup never makes the game fetch thousands of items.
function M:PriceCheckItemName(m)
 local n=m.name
 if type(n)=='string' and n~='' and not n:match('^Item %d+$') then return n end
 local id=tonumber(m.itemID);if not id then return nil end
 local cached=self.db.itemNames and self.db.itemNames[id]
 if type(cached)=='string' and cached~='' then return cached end
 if C_Item and C_Item.IsItemDataCachedByID then
  local ok,yes=pcall(C_Item.IsItemDataCachedByID,id)
  if not (ok and yes) then return nil end
 end
 local get=(C_Item and C_Item.GetItemNameByID) or GetItemInfo
 if not get then return nil end
 local ok,name=pcall(get,id)
 if ok and type(name)=='string' and name~='' then return name end
end
-- Find a typed name in our prices: the exact name first (suffix gear too:
-- "pagan belt of the bear"); else one item whose name holds the words.
-- Returns key,name,id or nil,{up to 3 close names}.
function M:FindPriceCheckItem(q)
 local exact,partial,seen,all=nil,{},{},{}
 local function consider(key,m,full)
  local n=full:lower()
  all[#all+1]={key,full,m.itemID,m}
  if n==q then
   if not exact or (m.lastSeen or 0)>(exact[4].lastSeen or 0) then exact={key,full,m.itemID,m} end
  elseif #q>=4 and n:find(q,1,true) and not seen[n] then
   seen[n]=true;partial[#partial+1]={key,full,m.itemID,m}
  end
 end
 for key,m in pairs(self.db.market) do
  if type(m)=='table' then
   local n=self:PriceCheckItemName(m)
   if n then consider(key,m,n) end
   if type(m.suffixFloors)=='table' then
    for full in pairs(m.suffixFloors) do if type(full)=='string' then consider(key,m,full) end end
   end
  end
 end
 if exact then return exact[1],exact[2],exact[3] end
 if #partial==1 then return partial[1][1],partial[1][2],partial[1][3] end
 if #partial==0 then
  -- Nothing holds the words: allow typos ("brnze bar", "bronze bars",
  -- "elixer of giants", "free action pot").
  local best,bestScore={},nil
  for _,e in ipairs(all) do
   local sc=self:TypoScore(q,e[2]:lower())
   if sc and not seen[e[2]:lower()] then
    if not bestScore or sc<bestScore-0.001 then best={e};bestScore=sc
    elseif math.abs(sc-bestScore)<=0.001 then best[#best+1]=e end
    seen[e[2]:lower()]=true
   end
  end
  if #best==1 then return best[1][1],best[1][2],best[1][3] end
  partial=best
 end
 table.sort(partial,function(a,b) return a[2]<b[2] end)
 local names={}
 for i=1,math.min(3,#partial) do names[i]=partial[i][2] end
 return nil,names,#partial
end
-- Typo distance (letters added, dropped, changed or swapped), giving up past cap.
local function distance(a,b,cap)
 local la,lb=#a,#b
 if math.abs(la-lb)>cap then return nil end
 local prev2,prev,cur={},{},{}
 for j=0,lb do prev[j]=j end
 for i=1,la do
  cur={[0]=i};local rowMin=i
  local ai=a:byte(i)
  for j=1,lb do
   local bj=b:byte(j)
   local c=math.min(prev[j]+1,cur[j-1]+1,prev[j-1]+(ai==bj and 0 or 1))
   if i>1 and j>1 and ai==b:byte(j-1) and a:byte(i-1)==bj then c=math.min(c,prev2[j-2]+1) end
   cur[j]=c;if c<rowMin then rowMin=c end
  end
  if rowMin>cap then return nil end
  prev2,prev=prev,cur
 end
 return prev[lb]<=cap and prev[lb] or nil
end
local FILLER={['of']=true,['the']=true,['a']=true}
local function clean(t) return (t:gsub("[%'%-%.,:]",''):gsub('%s+',' '):gsub('^ ',''):gsub(' $','')) end
local function words(t) local w={};for x in t:gmatch('%S+') do if not FILLER[x] then w[#w+1]=x end end;return w end
local function wordCap(n) return n>=9 and 2 or (n>=5 and 1 or 0) end
-- How close a typed name is to an item name: lower is closer, nil = not close.
-- Whole name with a few typos, or every typed word matching one of the
-- item's words (a typo each, or the start of it: "pot" for "potion").
function M:TypoScore(q,name)
 q,name=clean(q),clean(name)
 if #q<4 then return nil end
 local whole=distance(q,name,#q<=8 and 1 or (#q<=14 and 2 or 3))
 local qw,nw=words(q),words(name)
 local wordScore
 if #qw>0 and #qw<=#nw then
  local used,total=({}),0.5
  for _,w in ipairs(qw) do
   local hit
   for j,x in ipairs(nw) do
    if not used[j] then
     local d=(#w>=3 and x:sub(1,#w)==w) and 0.2 or distance(w,x,wordCap(#w))
     if d and (not hit or d<hit[2]) then hit={j,d} end
    end
   end
   if not hit then total=nil;break end
   used[hit[1]]=true;total=total+hit[2]
  end
  if total then wordScore=total+0.1*(#nw-#qw) end
 end
 if whole and wordScore then return math.min(whole,wordScore) end
 return whole or wordScore
end
-- The link for a found item when the game has it cached, else "[Name]".
local function displayFor(id,name)
 if id and GetItemInfo then
  local ok,_,link=pcall(GetItemInfo,id)
  if ok and type(link)=='string' and link:find('|Hitem:',1,true) and nameKey(link)==name:lower() then return link end
 end
 return '['..name..']'
end
-- What the last ask did, for /vmm pricecheck.
local function note(reason,from) PC.last={at=time(),reason=reason,from=from} end
function M:HandlePriceCheck(event,msg,sender)
 local ok,err=pcall(self.HandlePriceCheckInner,self,event,msg,sender)
 if not ok then
  note('error: '..tostring(err),sender)
  if not PC.errorShown then PC.errorShown=true;self:Print('Price check failed: '..tostring(err)..' (/vmm pricecheck)') end
 end
end
function M:HandlePriceCheckInner(event,msg,sender)
 local ch=CHANNELS[event];if not ch or not self.db or self.persistenceBlocked then return end
 if secret(msg,sender) then
  PC.secretSeen=(PC.secretSeen or 0)+1
  return
 end
 if type(msg)~='string' or type(sender)~='string' then return end
 local channel,setting=ch[1],ch[2]
 local target=channel=='WHISPER' and sender or nil
 if msg:sub(1,#PREFIX)==PREFIX then self:NotePriceCheckAnswer(channel,target,msg);return end
 local typed=self:PriceCheckTypedName(msg)
 if not typed and not self:IsPriceCheckAsk(msg) then return end
 if self.db.settings[setting]==false then note(channel..' replies are switched off in Settings',sender);return end
 if typed then return self:QueueTypedPriceCheck(typed,channel,target,sender) end
 local found=links(msg)
 if #found==0 then note('no item link found in: '..msg:gsub('|','||'),sender);return end
 note('reply queued ('..channel..')',sender)
 local t=now()
 for _,link in ipairs(found) do
  local text,has=self:PriceCheckReply(link)
  self:QueuePriceCheckReply(channel,target,nameKey(link),text,has)
 end
 self:SchedulePriceCheckFlush()
end
function M:QueuePriceCheckReply(channel,target,name,text,has)
 if not name or not text then return end
 local t=now()
 local k=place(channel,target)..'|'..name
 if PC.sent[k] and t-PC.sent[k]<REPEAT then return end
 -- Whispers are ours alone: answer at once. Shared channels: wait a moment.
 local delay=channel=='WHISPER' and 0 or (has and 0.4+math.random()*1.4 or 2.5+math.random())
 PC.sent[k]=t
 PC.pending[#PC.pending+1]={due=t+delay,asked=t,channel=channel,target=target,text=text,key=k}
end
function M:QueueTypedPriceCheck(q,channel,target,sender)
 local key,name,id=self:FindPriceCheckItem(q)
 if key~=nil then
  local text,has=self:PriceCheckReply(displayFor(id,name),key,name,id)
  note('reply queued for typed "'..q..'" ('..channel..')',sender)
  self:QueuePriceCheckReply(channel,target,name:lower(),text,has)
 elseif channel=='WHISPER' then
  -- Only whispers hear "not found": in guild/party another player's Market may know it.
  local close,count=name,id
  local text
  if type(close)=='table' and #close>0 then
   text=PREFIX..' "'..q..'" matches '..count..' items: '..table.concat(close,', ')..((count>3) and ', ...' or '')..'. Type the full name or link it.'
  else
   text=PREFIX..' no scan data for "'..q..'". Check the spelling or link the item.'
  end
  note('typed "'..q..'": not found, told them',sender)
  self:QueuePriceCheckReply(channel,target,'?'..q,cap(text),false)
 else
  note('typed "'..q..'": no item by that name in your scans',sender)
 end
 self:SchedulePriceCheckFlush()
end
function M:SchedulePriceCheckFlush()
 local soonest
 for _,r in ipairs(PC.pending) do if not soonest or r.due<soonest then soonest=r.due end end
 if not soonest then return end
 if C_Timer and C_Timer.After then
  C_Timer.After(math.max(0,soonest-now()),function() self:PriceCheckFlush() end)
 else
  self:PriceCheckFlush()
 end
end
function M:PriceCheckFlush()
 local t=now();local keep={}
 for _,r in ipairs(PC.pending) do
  if r.due>t+0.01 then keep[#keep+1]=r
  else
   local other=PC.answered[r.key]
   if other and other>=r.asked then
    if PC.last then PC.last.reason='another client answered first' end
   elseif (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage then
    if PC.lastSend and t-PC.lastSend<1 then r.due=PC.lastSend+1;keep[#keep+1]=r
    else
     PC.lastSend=t
     local send=(C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
     local ok,err=pcall(send,r.text,r.channel,nil,r.target)
     if PC.last then PC.last.reason=ok and ('sent to '..r.channel..(r.target and (' '..r.target) or '')) or ('send failed: '..tostring(err)) end
     if not ok and not PC.errorShown then PC.errorShown=true;self:Print('Price check reply failed: '..tostring(err)) end
    end
   end
  end
 end
 PC.pending=keep
 if #keep>0 and C_Timer and C_Timer.After then self:SchedulePriceCheckFlush() end
end
for event in pairs(CHANNELS) do
 M:RegisterHandler(event,function(self,ev,msg,sender) self:HandlePriceCheck(ev,msg,sender) end)
end

-- /vmm pricecheck: is it on, what happened to the last ask; with an item link,
-- shows here (not in chat) what the reply would be.
function M:PriceCheckStatus(arg)
 local st=self.db.settings
 local function on(k) return st[k]==false and 'off' or 'on' end
 self:Print('Price check: party/raid '..on('priceCheckParty')..', guild '..on('priceCheckGuild')..', whisper '..on('priceCheckWhisper')..' | version '..tostring(self.version))
 local l=PC.last
 if l then self:Print('Last ask from '..tostring(l.from)..' '..self:TooltipAgeText(l.at)..' ago: '..tostring(l.reason))
 else self:Print('No price check asks seen since login/reload.') end
 if (PC.secretSeen or 0)>0 then self:Print(PC.secretSeen..' chat line(s) were hidden from addons by the game (combat) and could not be read.') end
 if type(arg)=='string' and arg:find('|Hitem:',1,true) then
  local link=links(arg)[1]
  if link then self:Print('Would reply: '..tostring((self:PriceCheckReply(link)))) end
 elseif type(arg)=='string' and #arg>=3 then
  local key,name,id=self:FindPriceCheckItem(arg:lower())
  if key~=nil then self:Print('Would reply: '..tostring((self:PriceCheckReply(displayFor(id,name),key,name,id))))
  elseif type(name)=='table' and #name>0 then self:Print('"'..arg..'" matches '..id..' items: '..table.concat(name,', '))
  else self:Print('No item called "'..arg..'" in your scans.') end
 end
end
