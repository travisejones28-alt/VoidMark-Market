local _,M=...
-- Price check replies: someone asks for a price in party/raid/instance, guild
-- or a whisper and Market answers there with what your scans know.
--
--   pricecheck [Bronze Bar]        price check bronze bar       pc brnze bar?
--   pc 20 [Bronze Bar]             pc bronze bar x20            pc tin ore, copper ore
--   anyone pricecheck [Item]?      pc        (whisper: how to use it)
--
-- Answer: "VoidMark price: [Tin Ore] 1s (5,120 up, scanned 3m ago)".
-- Two clients (main + bank) or friends with Market may hear the same ask: each
-- waits a short random moment and stays quiet if someone already answered that
-- item there. A client with no price waits longer, so one with a price wins.
local PREFIX='VoidMark price:'
local CHANNELS={
 CHAT_MSG_PARTY={'PARTY','priceCheckParty'},CHAT_MSG_PARTY_LEADER={'PARTY','priceCheckParty'},
 CHAT_MSG_RAID={'RAID','priceCheckParty'},CHAT_MSG_RAID_LEADER={'RAID','priceCheckParty'},
 CHAT_MSG_INSTANCE_CHAT={'INSTANCE_CHAT','priceCheckParty'},CHAT_MSG_INSTANCE_CHAT_LEADER={'INSTANCE_CHAT','priceCheckParty'},
 CHAT_MSG_GUILD={'GUILD','priceCheckGuild'},CHAT_MSG_OFFICER={'OFFICER','priceCheckGuild'},
 CHAT_MSG_WHISPER={'WHISPER','priceCheckWhisper'}}
M.priceCheck=M.priceCheck or {}
local PC=M.priceCheck
PC.pending=PC.pending or {};PC.answered=PC.answered or {};PC.sent=PC.sent or {};PC.askers=PC.askers or {}
local REPEAT=30     -- same item in the same place answered at most once per 30s
local MAX_ITEMS=3   -- items answered per message
local PER_ASKER=6   -- asks answered per player per minute
local MAX_PENDING=15

local function now() return (GetTime and GetTime()) or time() end
local function cap(t) if #t>255 then return t:sub(1,252)..'...' end return t end
local function secret(...)
 if not issecretvalue then return false end
 for i=1,select('#',...) do if issecretvalue((select(i,...))) then return true end end
 return false
end
local function itemID(link) return tonumber(tostring(link):match('item:(%d+)')) end
-- Answers are matched by item name, so a linked ask and a typed one are the same.
local function nameKey(text) local n=tostring(text):match('%[(.-)%]');return n and n:lower() end
local function place(channel,target) return channel..'|'..(channel=='WHISPER' and tostring(target) or '') end
-- What the last ask did, for /vmm pricecheck.
local function note(reason,from) PC.last={at=time(),reason=reason,from=from} end

-- Plain text money for chat (chat can't show coin icons): "12g 3s 40c".
function M:PlainCoins(v)
 v=tonumber(v);if not v or v<1 then return '0c' end
 v=math.floor(v+0.5);local g,s,c=math.floor(v/10000),math.floor(v/100)%100,v%100
 local out={}
 if g>0 then out[#out+1]=g..'g' end
 if s>0 then out[#out+1]=s..'s' end
 if c>0 or #out==0 then out[#out+1]=c..'c' end
 return table.concat(out,' ')
end
local function commas(n)
 local s=tostring(math.floor(n));local out=s:reverse():gsub('(%d%d%d)','%1,'):reverse()
 return (out:gsub('^,',''))
end

-- Reading the ask ------------------------------------------------------------
-- Link colours come as |cffRRGGBB or, on newer clients, |cnIQ1: (by quality).
local function plainText(msg) return (msg:gsub('|c[^|]*',''):gsub('|H.-|h(.-)|h','%1'):gsub('|r','')) end
local LINK='|c[^|]*|Hitem:[^|]+|h%[.-%]|h|r'
local BARE_LINK='|Hitem:[^|]+|h%[.-%]|h'
local function trigger(l)
 return l:match('^%s*!?price%s*check%s*[:%-]?%s+(.-)%s*$') or l:match('^%s*!?pc%s*[:%-]?%s+(.-)%s*$')
  or l:match('^%s*!?pc(%[.-)%s*$')
  or ((l:match('^%s*!?price%s*check%s*[:%-]?%s*$') or l:match('^%s*!?pc%s*[:%-]?%s*$')) and '')
end
-- "20 bronze bar", "bronze bar x20", "bronze bar x 20", "20x bronze bar": count,name.
local function splitCount(t)
 local n,rest=t:match('^(%d+)%s*x?%s+(.+)$')
 if not n then rest,n=t:match('^(.-)%s*x%s*(%d+)$') end
 n=tonumber(n)
 if n and n>=1 and n<=10000 and rest and rest~='' then return math.floor(n),rest end
 return 1,t
end
-- Returns nil (not an ask) or {help=true} or {items={{link=..|text=..,count=n},...}}.
function M:ParsePriceCheck(msg)
 if type(msg)~='string' or msg:sub(1,#PREFIX)==PREFIX then return nil end
 local hasLink=msg:find('|Hitem:',1,true)~=nil
 local l=plainText(msg):lower()
 local rest=trigger(l)
 if hasLink then
  -- With a link "price check" may be anywhere ("anyone pricecheck [x]?").
  if not rest and not l:find('price%s*check') then return nil end
  local items={}
  local pattern=msg:find(LINK) and LINK or BARE_LINK
  local pos=1
  while #items<MAX_ITEMS do
   local a,b=msg:find(pattern,pos);if not a then break end
   local link=msg:sub(a,b)
   local before=plainText(msg:sub(pos,a-1)):lower()
   local after=plainText(msg:sub(b+1)):lower():match('^%s*x%s*(%d+)')
   local n=tonumber(after) or tonumber(before:match('(%d+)%s*x?%s*$'))
   items[#items+1]={link=link,count=(n and n>=1 and n<=10000) and math.floor(n) or 1}
   pos=b+1
  end
  if #items==0 then return nil end
  return {items=items}
 end
 if not rest then return nil end
 rest=rest:gsub('[%?!%.]+$',''):gsub('^%s+',''):gsub('%s+$','')
 if rest=='' or rest=='help' or rest=='?' then return {help=true} end
 local items={}
 for part in (rest..','):gmatch('([^,;/]+)[,;/]') do
  part=part:gsub('^%s+',''):gsub('%s+$',''):gsub('^and%s+',''):gsub('^%[(.-)%]$','%1')
  local n,name=splitCount(part)
  name=name:gsub('^%[(.-)%]$','%1')
  if #name>=3 and #items<MAX_ITEMS then items[#items+1]={text=name,count=n} end
 end
 if #items==0 then return {help=true} end
 return {items=items}
end
-- Kept for older callers and tests.
function M:IsPriceCheckAsk(msg) local p=self:ParsePriceCheck(msg);return p~=nil and p.items~=nil and p.items[1].link~=nil end
function M:PriceCheckTypedName(msg)
 local p=self:ParsePriceCheck(msg)
 return p and p.items and p.items[1].text or nil
end

-- Finding a typed name -------------------------------------------------------
-- An item's name for typed lookups. A full scan can save items the game hadn't
-- loaded yet with no name ("" or "Item 2771"), so fall back to remembered
-- names, then the game's cache. Only already-loaded items are asked for, so a
-- lookup never makes the game fetch thousands of items.
local function realName(n) return type(n)=='string' and n~='' and not n:match('^Item %d+$') and n or nil end
function M:PriceCheckItemName(m)
 local n=realName(m.name);if n then return n end
 local id=tonumber(m.itemID);if not id then return nil end
 n=realName(self.db.itemNames and self.db.itemNames[id]);if n then return n end
 if C_Item and C_Item.IsItemDataCachedByID then
  local ok,yes=pcall(C_Item.IsItemDataCachedByID,id)
  if not (ok and yes) then return nil end
 end
 local get=(C_Item and C_Item.GetItemNameByID) or GetItemInfo
 if not get then return nil end
 local ok,name=pcall(get,id)
 return ok and realName(name) or nil
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
  local used,total={},0.5
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
-- Find a typed name in our prices: the exact name first (suffix gear too:
-- "pagan belt of the bear"); else one item whose name holds the words; else
-- the one closest allowing typos. Returns key,name,id or nil,{up to 3 names},count.
function M:FindPriceCheckItem(q)
 q=q:lower()
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
    for full in pairs(m.suffixFloors) do if type(full)=='string' and full~=n then consider(key,m,full) end end
   end
  end
 end
 local hit
 if exact then hit=exact
 elseif #partial==1 then hit=partial[1]
 elseif #partial==0 then
  local best,bestScore,scored={},nil,{}
  for _,e in ipairs(all) do
   local n=e[2]:lower()
   if not scored[n] then
    scored[n]=true
    local sc=self:TypoScore(q,n)
    if sc then
     if not bestScore or sc<bestScore-0.001 then best={e};bestScore=sc
     elseif math.abs(sc-bestScore)<=0.001 then best[#best+1]=e end
    end
   end
  end
  if #best==1 then hit=best[1] else partial=best end
 end
 if hit then
  -- Remember a name we had to look up, so it's found even after a relog.
  local id=tonumber(hit[3])
  if id and not realName(hit[4].name) and not realName(self.db.itemNames[id]) and not self.persistenceBlocked
   and not (type(hit[4].suffixFloors)=='table' and hit[4].suffixFloors[hit[2]]) then self.db.itemNames[id]=hit[2] end
  return hit[1],hit[2],hit[3]
 end
 table.sort(partial,function(a,b) return a[2]<b[2] end)
 local names={}
 for i=1,math.min(3,#partial) do names[i]=partial[i][2] end
 return nil,names,#partial
end
-- The link for a found item when the game has it cached, else "[Name]".
local function displayFor(id,name)
 if id and GetItemInfo then
  local ok,_,link=pcall(GetItemInfo,id)
  if ok and type(link)=='string' and link:find('|Hitem:',1,true) and nameKey(link)==name:lower() then return link end
 end
 return '['..name..']'
end

-- The answer -----------------------------------------------------------------
-- display: the link, or "[Name]" for a typed name (with key/name/id from the
-- lookup). Returns the reply and whether we had a price.
function M:PriceCheckReply(display,key,name,id,count)
 if not self.db then return nil end
 if not name then key=self:LinkIdentity(display);name=self:LinkName(display);id=itemID(display) end
 count=tonumber(count) or 1
 local m=key~=nil and self.db.market[key]
 local p,listed
 if key~=nil then
  local state,sf=self:VariantPrice(key,name,name)
  if state=='suffix' then p={floor=sf.floor,at=sf.at};listed=sf.quantity
  elseif state=='key' then
   p=self:PriceObservation(key)
   listed=p and (p.quantity or (m and type(m.latest)=='table' and m.latest.quantity))
  end
 end
 local tp=(key==nil or self:VariantPrice(key,name,name)~='none') and self:TSMPrice(id or display)
 local head=PREFIX..' '..(count>1 and (count..'x ') or '')..display..' '
 local function price(each)
  if count>1 then return self:PlainCoins(each*count)..' ('..self:PlainCoins(each)..' each' end
  return self:PlainCoins(each)..' ('
 end
 if not p or not self:Finite(p.floor,1,1e12) then
  if tp then return cap(head..price(tp)..(count>1 and ', ' or '')..'TSM)'),true end
  return cap(PREFIX..' '..display..' no scan data'),false
 end
 -- Ours is from an earlier day and TSM has one: TSM's is fresher.
 if tp and time()-p.at>=86400 then
  return cap(head..price(tp)..(count>1 and ', ' or '')..'TSM; our scan '..self:TooltipAgeText(p.at)..' old)'),true
 end
 local parts={}
 if self.MissedLatestScan and self:MissedLatestScan(p) then
  parts[#parts+1]='none up in last scan, last seen '..self:TooltipAgeText(p.at)..' ago'
 else
  if self:Finite(listed,1,1e9) then parts[#parts+1]=commas(listed)..' up' end
  parts[#parts+1]='scanned '..self:TooltipAgeText(p.at)..' ago'
 end
 if self:Finite(p.fair,1,1e12) and math.abs(p.fair-p.floor)>=p.floor*0.1 then
  parts[#parts+1]='usually '..self:PlainCoins(p.fair)
 end
 local text=head..price(p.floor)..(count>1 and '; ' or '')..table.concat(parts,', ')..')'
 if count>1 and self:Finite(listed,1,1e9) and listed<count then text=text..' - only '..commas(listed)..' up' end
 return cap(text),true
end
local HELP=PREFIX..' type "pc" and an item link or name, e.g. "pc tin ore", "pc 20 bronze bar" or "pc [item]".'

-- Handling chat --------------------------------------------------------------
function M:NotePriceCheckAnswer(channel,target,msg)
 if type(msg)~='string' or msg:sub(1,#PREFIX)~=PREFIX then return end
 local n=nameKey(msg);if not n then return end
 PC.answered[place(channel,target)..'|'..n]=now()
end
function M:HandlePriceCheck(event,msg,sender)
 local ok,err=pcall(self.HandlePriceCheckInner,self,event,msg,sender)
 if not ok then
  note('error: '..tostring(err),sender)
  if not PC.errorShown then PC.errorShown=true;self:Print('Price check failed: '..tostring(err)..' (/vmm pricecheck)') end
 end
end
-- A player asking a lot: at most PER_ASKER asks a minute are answered.
local function askerAllowed(sender,t)
 local list=PC.askers[sender] or {}
 local keep={}
 for _,at in ipairs(list) do if t-at<60 then keep[#keep+1]=at end end
 if #keep>=PER_ASKER then PC.askers[sender]=keep;return false end
 keep[#keep+1]=t;PC.askers[sender]=keep;return true
end
function M:HandlePriceCheckInner(event,msg,sender)
 local ch=CHANNELS[event];if not ch or not self.db or self.persistenceBlocked then return end
 if secret(msg,sender) then PC.secretSeen=(PC.secretSeen or 0)+1;return end
 if type(msg)~='string' or type(sender)~='string' then return end
 local channel,setting=ch[1],ch[2]
 local target=channel=='WHISPER' and sender or nil
 if msg:sub(1,#PREFIX)==PREFIX then self:NotePriceCheckAnswer(channel,target,msg);return end
 local ask=self:ParsePriceCheck(msg)
 if not ask then return end
 if self.db.settings[setting]==false then note(channel..' replies are switched off in Settings',sender);return end
 if not askerAllowed(sender,now()) then note('too many asks from '..sender..' this minute',sender);return end
 if ask.help then
  -- Only a whisper gets the how-to; "pc" alone in guild is likely something else.
  if channel=='WHISPER' then note('sent how to use it',sender);self:QueuePriceCheckReply(channel,target,'?help',HELP,false) end
  return self:SchedulePriceCheckFlush()
 end
 note('reply queued ('..channel..')',sender)
 for _,it in ipairs(ask.items) do
  if it.link then
   local text,has=self:PriceCheckReply(it.link,nil,nil,nil,it.count)
   self:QueuePriceCheckReply(channel,target,nameKey(it.link),text,has)
  else
   self:QueueTypedPriceCheck(it.text,channel,target,sender,it.count)
  end
 end
 self:SchedulePriceCheckFlush()
end
function M:QueuePriceCheckReply(channel,target,name,text,has)
 if not name or not text or #PC.pending>=MAX_PENDING then return end
 local t=now()
 local k=place(channel,target)..'|'..name
 if PC.sent[k] and t-PC.sent[k]<REPEAT then return end
 -- Whispers are ours alone: answer at once. Shared channels: wait a moment.
 local delay=channel=='WHISPER' and 0 or (has and 0.4+math.random()*1.4 or 2.5+math.random())
 PC.sent[k]=t
 PC.pending[#PC.pending+1]={due=t+delay,asked=t,channel=channel,target=target,text=text,key=k}
end
function M:QueueTypedPriceCheck(q,channel,target,sender,count)
 local key,name,id=self:FindPriceCheckItem(q)
 if key~=nil then
  local text,has=self:PriceCheckReply(displayFor(id,name),key,name,id,count)
  note('reply queued for "'..q..'" -> '..name..' ('..channel..')',sender)
  self:QueuePriceCheckReply(channel,target,name:lower(),text,has)
 elseif channel=='WHISPER' then
  -- Only whispers hear "not found": in guild/party another player's Market may know it.
  local close,n=name,id
  local text
  if type(close)=='table' and #close>0 then
   text=PREFIX..' "'..q..'" matches '..n..' items: '..table.concat(close,', ')..((n>3) and ', ...' or '')..'. Type the full name or link it.'
  else
   text=PREFIX..' no scan data for "'..q..'". Check the spelling or link the item.'
  end
  note('"'..q..'": not found, told them',sender)
  self:QueuePriceCheckReply(channel,target,'?'..q,cap(text),false)
 else
  note('"'..q..'": no item by that name in your scans',sender)
 end
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
   local send=(C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
   if other and other>=r.asked then
    if PC.last then PC.last.reason='another client answered first' end
   elseif send then
    -- At most one reply a second.
    if PC.lastSend and t-PC.lastSend<1 then r.due=PC.lastSend+1;keep[#keep+1]=r
    else
     PC.lastSend=t
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

-- /vmm pricecheck: is it on, what happened to the last ask. With an item link
-- or name it shows here (not in chat) what the reply would be.
function M:PriceCheckStatus(arg)
 local st=self.db.settings
 local function on(k) return st[k]==false and 'off' or 'on' end
 self:Print('Price check: party/raid '..on('priceCheckParty')..', guild '..on('priceCheckGuild')..', whisper '..on('priceCheckWhisper')..' | version '..tostring(self.version))
 local l=PC.last
 if l then self:Print('Last ask from '..tostring(l.from)..' '..self:TooltipAgeText(l.at)..' ago: '..tostring(l.reason))
 else self:Print('No price check asks seen since login/reload.') end
 if (PC.secretSeen or 0)>0 then self:Print(PC.secretSeen..' chat line(s) were hidden from addons by the game (combat) and could not be read.') end
 if type(arg)~='string' or #arg<3 then return end
 local ask=self:ParsePriceCheck('pc '..arg)
 if not ask or not ask.items then return end
 for _,it in ipairs(ask.items) do
  if it.link then self:Print('Would reply: '..tostring((self:PriceCheckReply(it.link,nil,nil,nil,it.count))))
  else
   local key,name,id=self:FindPriceCheckItem(it.text)
   if key~=nil then self:Print('Would reply: '..tostring((self:PriceCheckReply(displayFor(id,name),key,name,id,it.count))))
   elseif type(name)=='table' and #name>0 then self:Print('"'..it.text..'" matches '..id..' items: '..table.concat(name,', '))
   else self:Print('No item called "'..it.text..'" in your scans.') end
  end
 end
end
