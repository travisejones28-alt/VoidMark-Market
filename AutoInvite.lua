-- VoidMark auto-invite. The same file ships in every VoidMark addon; the first
-- one loaded runs it and the others stand down, so you never get two invites.
-- A whisper of "inv" or "invite" from a character whose first name is
-- Voidmark (your own characters) gets a group invite.
if _G.VoidMarkAutoInvite then return end
local A={version=1,last={}}
_G.VoidMarkAutoInvite=A

local WORDS={inv=true,invite=true}
local COOLDOWN=5 -- seconds between invites to the same character

local function safe(fn,...)
  if type(fn)~='function' then return nil end
  local ok,v=pcall(fn,...)
  if not ok then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- "Voidmark Soulreaver", "Voidmark Soulreaver-Realm", "Voidmark-Soulreaver".
function A.IsVoidmark(sender)
  if type(sender)~='string' then return false end
  local first=sender:match('^%s*([^%s%-]+)')
  return first~=nil and first:lower()=='voidmark'
end

-- "inv", "invite", "Inv!", " INVITE " - the whole whisper, nothing else.
function A.Wants(msg)
  if type(msg)~='string' then return false end
  local m=msg:lower():gsub('^%s+',''):gsub('%s+$',''):gsub('%p+$','')
  return WORDS[m]==true
end

local function baseName(name) return (tostring(name or ''):gsub('%-[^%s%-]+$','')) end

function A.CanInvite()
  local inGroup=safe(IsInGroup)
  if not inGroup then return true end
  return safe(UnitIsGroupLeader,'player') or safe(UnitIsGroupAssistant,'player') or false
end

function A.Invite(name)
  if A.blocked then return false end
  if C_PartyInfo and C_PartyInfo.InviteUnit then return pcall(C_PartyInfo.InviteUnit,name) end
  if InviteUnit then return pcall(InviteUnit,name) end
  return false
end

function A.OnWhisper(msg,sender)
  if not A.Wants(msg) or not A.IsVoidmark(sender) then return false end
  local me=safe(UnitName,'player')
  if me and baseName(sender)==me then return false end
  local short=baseName(sender)
  if safe(UnitInParty,short) or safe(UnitInRaid,short) then return false end
  if not A.CanInvite() then return false end
  local now=(GetTime and GetTime()) or 0
  if A.last[short] and now-A.last[short]<COOLDOWN then return false end
  A.last[short]=now
  A.Invite(sender)
  return true
end

if CreateFrame then
  local f=CreateFrame('Frame')
  f:RegisterEvent('CHAT_MSG_WHISPER')
  f:SetScript('OnEvent',function(_,_,msg,sender) A.OnWhisper(msg,sender) end)
  A.frame=f
end
