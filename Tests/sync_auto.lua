return function(M,check,jobs,advance)
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
end
check('Automatic named pairing preserves explicit peer and off across reload',function()
 local old,nu,un=UnitName,NameUtil,UnitNameUnmodified
 NameUtil=nil;UnitNameUnmodified=nil;UnitName=function() return 'Voidmark Soulreaver' end
 reset();assert(M.db.syncPeer=='voidmark bank-testrealm')
 M:PairPeer('off');M:InitializeDatabase();jobs();assert(not M.db.syncPeer)
 UnitName=function()return 'Voidmark Bank' end
 reset();assert(M.db.syncPeer=='voidmark soulreaver-testrealm')
 local peer=M.db.syncPeer
 assert(M:PairPeer('Other Name-OtherRealm')=='Peer must be on the same realm' and M.db.syncPeer==peer)
 -- Forever First-Surname with a hyphen pairs as "First Surname" on this realm.
 M:PairPeer('Voidmark-Soulreaver');assert(M.db.syncPeer=='voidmark soulreaver-testrealm')
 -- Surname in UnitName's second slot (Forever) still auto-pairs.
 UnitName=function()return 'Voidmark','Soulreaver' end
 reset();assert(M.db.syncPeer=='voidmark bank-testrealm')
 UnitName,NameUtil,UnitNameUnmodified=old,nu,un
 reset()
 -- A partner reported as "First-Surname" (with or without realm) is the paired partner.
 M:PairPeer('Voidmark Bank');M.shareRun={}
 for _,sender in ipairs({'Voidmark-Bank','Voidmark Bank-TestRealm','Voidmark-Bank-TestRealm'}) do
  M.shareRun={};M:ReceiveSharing('VMMkt2',M.economyID..'\tH\t1-1','WHISPER',sender)
  assert(M.shareRun.status=='Partner connected',sender)
 end
 M.shareRun={};M:ReceiveSharing('VMMkt2',M.economyID..'\tH\t1-1','WHISPER','Voidmark-Soulreaver');assert(M.shareRun.status~='Partner connected')
 M:PairPeer('off')
end)
check('Automatic bank scan requires AH and cooldown and bounds failed retries',function()
 local old,nu,un,request,combat=UnitName,NameUtil,UnitNameUnmodified,M.RequestFreshScan,InCombatLockdown
 NameUtil=nil;UnitNameUnmodified=nil;UnitName=function()return 'Voidmark Bank' end
 reset();local n=0;M.RequestFreshScan=function()n=n+1 end
 M.autoScanNext=nil;M.autoScanCheck=nil;M.ahOpen=false
 M:AutomaticBankScan(GetTime());assert(n==0)
 advance(6);M.ahOpen=true;InCombatLockdown=function()return true end
 M:AutomaticBankScan(GetTime());assert(n==0)
 advance(6);InCombatLockdown=function()return false end
 M.db.lastFreshScanRequestAt=time();M:AutomaticBankScan(GetTime());assert(n==0)
 advance(901);M:AutomaticBankScan(GetTime());assert(n==1)
 advance(10);M:AutomaticBankScan(GetTime());assert(n==1)
 advance(301);M.db.settings.autoBankScan=false;M:AutomaticBankScan(GetTime());assert(n==1)
 advance(6);M.db.settings.autoBankScan=true;M:AutomaticBankScan(GetTime());assert(n==2)
 -- 1.22.25: never while a buy page is open, or within 2 minutes of shopping/selling.
 advance(301);M.shopBuy={};M:AutomaticBankScan(GetTime());assert(n==2,'not while buying')
 M.shopBuy=nil;M.lastUserAHAction=GetTime();advance(6);M:AutomaticBankScan(GetTime());assert(n==2,'not right after shopping')
 advance(120);M:AutomaticBankScan(GetTime());assert(n==3,'resumes after 2 minutes')
 M.lastUserAHAction=nil
 UnitName,NameUtil,UnitNameUnmodified,M.RequestFreshScan,InCombatLockdown=old,nu,un,request,combat
 reset()
end)
check('Sync diagnostics distinguish received pages and complete transfers; force preserves financial data',function()
 reset();M:PairPeer('Bank');M.shareRun={};local d=M.db;d.ledger[1]={id=999}
 local epoch='123-999';local prefix=M.economyID..'\t'
 M:ReceiveSharing('VMMkt2',prefix..'H\t'..epoch,'WHISPER','Bank-TestRealm')
 M:ReceiveSharing('VMMkt2',prefix..'I\t'..epoch..'\t2\t'..time(),'WHISPER','Bank-TestRealm')
 local function page(lo,hi,id)
  M:ReceiveSharing('VMMkt2',prefix..table.concat({'D',epoch,lo,hi,'P,'..id..','..time()..',100,0'},'\t'),'WHISPER','Bank-TestRealm')
 end
 M:SetView('browse');page(0,1,77661);jobs()
 assert(d.syncLastReceivedAt and not d.syncLastReceivedCompleteAt)
 local found=false;for _,r in ipairs(M.browseRows) do if r.itemID==77661 then found=true;assert(r.status=='SYNCED') end end;assert(found)
 page(1,2,77662);assert(d.syncLastReceivedCompleteAt)
 assert(d.shareReceived[d.syncPeer].scanAt==time())
 local journal=d.shareJournal;local received=d.shareReceived;local ledger=d.ledger
 M:ReconnectSharing(true);assert(d.shareJournal==journal and d.shareReceived==received and d.ledger==ledger and ledger[1].id==999)
 M:SetView('sync');M:RenderUI();jobs();M:RenderUI()
 assert(M.syncFrame:IsShown() and M.syncReport:GetText():find('Received prices: 2',1,true))
 M:SetView('crafting');M:RenderUI();assert(not M.syncFrame:IsShown())
 M:SetView('browse');M:RenderUI();assert(not M.syncFrame:IsShown())
 advance(M.db.settings.maxDataAge+10);M:BuildBrowseRows('77661');jobs()
 assert(M.browseRows[1].status=='SYNC STALE' and not M.browseRows[1].modelReady)
 assert(not d.market[77661] and #d.ledger==1)
 reset()
end)
check('1.23.51 bank scan counts as received at its end marker, not when the growing total is reached',function()
 reset();M:PairPeer('Bank');M.shareRun={};local d=M.db
 local epoch='123-777';local prefix=M.economyID..'\t';local T=time()-360
 local function msg(...) M:ReceiveSharing('VMMkt2',prefix..table.concat({...},'\t'),'WHISPER','Bank-TestRealm') end
 local function page(lo,hi,id) msg('D',epoch,lo,hi,'P,'..id..','..T..',100,0') end
 msg('H',epoch);msg('I',epoch,'50',tostring(T));msg('S',epoch,'2',tostring(T))
 local rx=d.shareReceived[d.syncPeer];assert(rx.scanSeq==2 and rx.scanSeqAt==T)
 page(0,1,77671);jobs();M.shareRun.lastContact=GetTime()
 assert(M:SimpleSyncStatus()=='Bank sync: receiving bank scan 50%',M:SimpleSyncStatus())
 assert(not M:PartnerScanReceived(rx) and M:NewestFullScanAt()~=T)
 page(1,2,77672);jobs();M.shareRun.lastContact=GetTime()
 assert(M:PartnerScanReceived(rx) and rx.seq<rx.total,'scan done while refreshes still pending')
 assert(M:NewestFullScanAt()==T and d.syncLastReceivedCompleteAt)
 assert(M:SimpleSyncStatus():find('connected | bank scan 6 min ago',1,true),M:SimpleSyncStatus())
 d.latestScan={completedAt=time()-86400*10,auctionsProcessed=204122}
 assert(M:SimpleScanStatus():find('Last scan: 6 min ago (from bank sync)',1,true),M:SimpleScanStatus())
 -- A newer scan announced without its end marker is not trusted early.
 msg('I',epoch,'60',tostring(T+300));assert(not M:PartnerScanReceived(rx))
 assert(M:SimpleSyncStatus():find('receiving',1,true))
 msg('S',epoch,'55',tostring(T+300));assert(not M:PartnerScanReceived(rx))
 -- Bad markers are ignored.
 msg('S',epoch,'x',tostring(T));msg('S','9-9','3',tostring(T));assert(rx.scanSeq==55)
 reset()
end)
check('1.23.51 bank sends where its scan ends right after the scan announcement',function()
 reset();local oldChat,oldGroup=C_ChatInfo,GetNumGroupMembers;local sent={}
 GetNumGroupMembers=function() return 0 end
 C_ChatInfo={RegisterAddonMessagePrefix=function() return 0 end,SendAddonMessage=function(_,body) sent[#sent+1]=body;return 0 end}
 M:PairPeer('Voidmark Bank');local d=M.db;local j=d.shareJournal
 j.seq=40;d.lastDepthSnapshotAt=time()-60;d.shareScanSeq=37;d.shareScanSeqAt=d.lastDepthSnapshotAt
 M.shareRun.lastContact=GetTime();M.shareRun.infoPending=true;M.shareRun.hello=GetTime()+20;M.shareRun.next=0
 M:PumpSharing()
 local info,marker
 for _,b in ipairs(sent) do if b:find('\tI\t',1,true) then info=b end;if b:find('\tS\t',1,true) then marker=b end end
 assert(info,'I sent');assert(marker and marker:find('\tS\t'..j.epoch..'\t37\t'..d.lastDepthSnapshotAt,1,true),tostring(marker))
 C_ChatInfo,GetNumGroupMembers=oldChat,oldGroup;M:PairPeer('off');reset()
end)
end
