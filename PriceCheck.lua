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
 local plain=msg:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|H.-|h(.-)|h','%1'):gsub('|r',''):lower()
 return plain:find('price%s*check')~=nil or plain:find('^%s*!?pc%s')~=nil or plain:find('^%s*!?pc%[')~=nil
end
local function links(msg)
 local out={}
 for link in msg:gmatch('|c%x+|Hitem:[^|]+|h%[.-%]|h|r') do
  out[#out+1]=link;if #out>=MAX_LINKS then break end
 end
 if #out==0 then
  for link in msg:gmatch('|Hitem:[^|]+|h%[.-%]|h') do out[#out+1]=link;if #out>=MAX_LINKS then break end end
 end
 return out
end
local function itemID(link) return tonumber(tostring(link):match('item:(%d+)')) end
-- Reply text for one link, and whether we had a price at all.
function M:PriceCheckReply(link)
 if not self.db then return nil end
 local key=self:LinkIdentity(link)
 local name=self:LinkName(link)
 local p
 if key~=nil then
  local state,sf=self:VariantPrice(key,name,name)
  if state=='suffix' then p={floor=sf.floor,at=sf.at}
  elseif state=='key' then p=self:PriceObservation(key) end
 end
 if not p or not self:Finite(p.floor,1,1e12) then return PREFIX..' '..link..' no scan data',false end
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
 return text,true
end
-- Someone (us on another client, a friend) already answered this item here.
local function place(channel,target) return channel..'|'..(channel=='WHISPER' and tostring(target) or '') end
function M:NotePriceCheckAnswer(channel,target,msg)
 if type(msg)~='string' or msg:sub(1,#PREFIX)~=PREFIX then return end
 local id=itemID(msg);if not id then return end
 PC.answered[place(channel,target)..'|'..id]=now()
end
function M:HandlePriceCheck(event,msg,sender)
 local ch=CHANNELS[event];if not ch or not self.db or self.persistenceBlocked then return end
 if type(msg)~='string' or type(sender)~='string' then return end
 local channel,setting=ch[1],ch[2]
 if self.db.settings[setting]==false then return end
 local target=channel=='WHISPER' and sender or nil
 if msg:sub(1,#PREFIX)==PREFIX then self:NotePriceCheckAnswer(channel,target,msg);return end
 if not self:IsPriceCheckAsk(msg) then return end
 local t=now()
 for _,link in ipairs(links(msg)) do
  local id=itemID(link)
  local k=place(channel,target)..'|'..tostring(id)
  if id and not (PC.sent[k] and t-PC.sent[k]<REPEAT) then
   local text,has=self:PriceCheckReply(link)
   if text then
    -- Whispers are ours alone: answer at once. Shared channels: wait a moment.
    local delay=channel=='WHISPER' and 0 or (has and 0.4+math.random()*1.4 or 2.5+math.random())
    PC.sent[k]=t
    PC.pending[#PC.pending+1]={due=t+delay,asked=t,channel=channel,target=target,text=text,key=k}
   end
  end
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
   if not (other and other>=r.asked) and SendChatMessage then
    pcall(SendChatMessage,r.text,r.channel,nil,r.target)
   end
  end
 end
 PC.pending=keep
end
for event in pairs(CHANNELS) do
 M:RegisterHandler(event,function(self,ev,msg,sender) self:HandlePriceCheck(ev,msg,sender) end)
end
