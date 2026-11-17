local _,M=...
-- 1.24.2: "VoidMarkMarket has been blocked from an action only available to
-- the Blizzard UI." The game's popup doesn't say what was blocked. Record it,
-- say it in chat, and stop the feature that caused it for this session, so the
-- popup can't keep coming back. Things that run on their own (no click) are
-- the candidates: price check auto-replies (chat) and the auto-invite.
function M:OnActionBlocked(event,addon,fn)
 if addon~=self.name then return end
 fn=tostring(fn or 'unknown')
 local what
 if fn:find('SendChatMessage',1,true) then
  self.priceCheckBlocked=true;what='a price check reply'
 elseif fn:find('InviteUnit',1,true) then
  if _G.VoidMarkAutoInvite then _G.VoidMarkAutoInvite.blocked=true end;what='an auto-invite'
 elseif fn:find('Reload',1,true) then what='the Reload button'
 end
 local doing=self.lastAutoAction and GetTime()-self.lastAutoAction.at<5 and self.lastAutoAction.what or nil
 local rec={fn=fn,event=tostring(event),at=time(),what=what or doing}
 if self.db then
  self.db.blockedActions=type(self.db.blockedActions)=='table' and self.db.blockedActions or {}
  local list=self.db.blockedActions;list[#list+1]=rec;while #list>10 do table.remove(list,1) end
 end
 self.blockedSeen=self.blockedSeen or {}
 if not self.blockedSeen[fn] then
  self.blockedSeen[fn]=true
  self:Print('The game blocked '..fn..(rec.what and (' ('..rec.what..')') or '')..
   (what and '. That is off until your next /reload. Click Ignore; nothing was lost.' or '. Click Ignore; nothing was lost.'))
 end
end
M:RegisterHandler('ADDON_ACTION_BLOCKED',function(self,event,...) self:OnActionBlocked(event,...) end)
M:RegisterHandler('ADDON_ACTION_FORBIDDEN',function(self,event,...) self:OnActionBlocked(event,...) end)
