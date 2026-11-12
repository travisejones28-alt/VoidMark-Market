return function(M,check,jobs,advance,emit)
-- 1.9.6 bank sync status freshness and reconnect speed.
local function reset()
 C_ChatInfo={RegisterAddonMessagePrefix=function() return 0 end,SendAddonMessage=function() return 0 end}
 GetNumGroupMembers=function() return 0 end
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs();M:InitializeUI()
end
check('1.9.6 Bank sync header updates on every view without a full redraw',function()
 reset();M:PairPeer('Bank');M.shareRegistered=true
 M:SetView('selling');M.window:Show();M:RenderUI()
 assert(M.connectionLabel:GetText()=='Bank sync: waiting for partner')
 local epoch='123-999'
 M:ReceiveSharing('VMMkt2',M.economyID..'\tH\t'..epoch,'WHISPER','Bank-TestRealm')
 M.uiDirty=false;M.syncLabelAt=nil
 M:PumpSharing()
 assert(M.connectionLabel:GetText()~='Bank sync: waiting for partner','label must follow the handshake')
 advance(70);M.syncLabelAt=nil;M.uiDirty=false;M:PumpSharing()
 assert(M.connectionLabel:GetText()=='Bank sync: waiting for partner','label must follow contact loss')
end)
check('1.9.6 Unanswered probes retry within a minute and an offline notice waits only 1m',function()
 reset();M:PairPeer('Bank');M.shareRegistered=true
 for _=1,8 do M.shareRun.hello=nil;M.shareRun.next=0;M:PumpSharing() end
 assert(M.shareRun.probeDelay<=30)
 local template=ERR_CHAT_PLAYER_NOT_FOUND or "No player named '%s' is currently playing."
 assert(M:HandlePeerOfflineNotice(string.format(template,'Bank')))
 assert(M.shareRun.offlineUntil-GetTime()<=30)
 emit('PLAYER_ENTERING_WORLD')
 assert(M.shareRun.offlineUntil==nil and M.shareRun.hello==nil)
end)
end
