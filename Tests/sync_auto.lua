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
end
