local invites={};local t=100
GetTime=function() return t end
UnitName=function() return 'Voidmark Soulreaver' end
local inGroup,leader=false,false
IsInGroup=function() return inGroup end
UnitIsGroupLeader=function() return leader end
UnitIsGroupAssistant=function() return false end
UnitInParty=function() return false end;UnitInRaid=function() return nil end
C_PartyInfo={InviteUnit=function(n) invites[#invites+1]=n end}
local handler
CreateFrame=function() return {RegisterEvent=function() end,SetScript=function(_,_,fn) handler=fn end} end
dofile(arg and arg[1] or 'AutoInvite.lua')
local A=VoidMarkAutoInvite
local function w(msg,from) handler(nil,'CHAT_MSG_WHISPER',msg,from) end
w('inv','Voidmark Bank');assert(invites[1]=='Voidmark Bank','inv from Voidmark Bank')
w('INVITE!','Voidmark Herbstorage-Realm');assert(invites[2]=='Voidmark Herbstorage-Realm')
w('inv','Voidmark Bank');assert(#invites==2,'5s cooldown')
t=110;w('inv','Voidmark Bank');assert(#invites==3,'after cooldown')
w('inv','Bob Smith');w('inv me pls','Voidmark Kitty');w('inv','Voidmarker Kitty');assert(#invites==3,'only Voidmark first name, only inv/invite')
w('inv','Voidmark Soulreaver');assert(#invites==3,'not yourself')
inGroup=true;t=200;w('inv','Voidmark Kitty');assert(#invites==3,'in a group, not leader: no invite')
leader=true;w('inv','Voidmark Kitty');assert(#invites==4,'leader invites')
-- second copy stands down
local before=handler;dofile(arg and arg[1] or 'AutoInvite.lua');assert(VoidMarkAutoInvite==A and handler==before,'second copy stands down')
print('PASS auto-invite')
