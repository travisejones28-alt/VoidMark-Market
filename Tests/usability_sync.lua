return function(M,check,jobs,advance)
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
end
check('Shared stack prices round up fractional copper and publish scan-completion metadata',function()
 reset();M:PairPeer('Bank');jobs()
 local m={marketKey=81234,itemID=81234,name='Stack',lastSeen=time(),latest={floor=12.5},confidenceScore=0}
 M.db.market[81234]=m;M.marketIndex={81234};M.db.lastDepthSnapshotAt=time()
 M:PublishPrice(m)
 local j=M.db.shareJournal;local line=j.rows[j.latest.P81234]
 assert(line and line:find(',13,0,0',1,true))
 local seq=j.seq;advance(1);m.lastSeen=time();M:PublishPrice(m)
 assert(j.seq==seq+1 and j.rows[j.seq]:sub(1,2)=='U,')
 M.shareRun.infoPending=nil;M:QueueScanSharing(m.lastSeen);jobs()
 assert(M.shareRun.infoPending and M.shareRun.next==0)
 reset()
end)
check('Sync accepts realm display spaces but rejects another realm or faction',function()
 reset();M:PairPeer('Bank');local epoch='123-888';local peer='Bank-TestRealm'
 M:ReceiveSharing('VMMkt2','Test Realm|Horde\tH\t'..epoch,'WHISPER',peer)
 assert(M.shareRun.lastContact and M.shareRun.reply)
 M:ReceiveSharing('VMMkt2','Test Realm|Horde\tI\t'..epoch..'\t1\t'..time(),'WHISPER',peer)
 M:ReceiveSharing('VMMkt2','Test Realm|Horde\tD\t'..epoch..'\t0\t1\tP,81235,'..time()..',123,0','WHISPER',peer)
 assert(M.db.sharedPrices[81235].floor==123 and M.db.syncLastReceivedCompleteAt)
 M:ReceiveSharing('VMMkt2','OtherRealm|Horde\tH\t123-999','WHISPER',peer)
 assert(M.db.shareReceived[M.db.syncPeer].epoch==epoch)
 M:ReceiveSharing('VMMkt2','TestRealm|Alliance\tH\t123-999','WHISPER',peer)
 assert(M.db.shareReceived[M.db.syncPeer].epoch==epoch)
 reset()
end)
check('Simple trading uses item-name search, list sidebar, useful empty states and separate tools',function()
 reset();M.shoppingListMode=false;M.shoppingSearchStatus=nil;M.browseRows={}
 M:SetView('browse');jobs();M:RenderUI()
 assert(M.shoppingSidebar:IsShown() and M.searchButton:IsShown() and M.scanButton:IsShown())
 assert(not M.cachedButton:IsShown() and not M.toolsFrame:IsShown())
 assert(M.emptyMessage:IsShown() and M.emptyMessage:GetText():find('Search by item name',1,true))
 assert(M.tableFrame:GetWidth()==788 and not M.headings[6]:IsShown())
 M:SetView('tools');M:RenderUI()
 assert(M.toolsFrame:IsShown() and not M.tableFrame:IsShown() and not M.toolbar:IsShown() and not M.shoppingSidebar:IsShown())
 M.db.latestScan={auctionsProcessed=100,completedAt=time()};M.scanState.running=false;M.scanState.phase='done'
 M:SetView('vendor');M:RenderUI();assert(M.emptyMessage:GetText():find('No below-vendor deals',1,true))
 M.scanState.phase='error';assert(M:SimpleScanStatus():find('Scan failed',1,true))
 M.scanState.running=true;M.scanState.phase='processing';M.scanState.processed=5;M.scanState.snapshotRows=100
 assert(M:SimpleScanStatus():find('5 / 100',1,true))
 M.scanState.running=false;M.scanState.phase='done'
 reset()
end)
check('Saved shopping results use received prices and keep target-based buying available',function()
 reset();M:PairPeer('Bank');M.db.sharedPrices[81236]={id=81236,key=81236,at=time(),floor=123,reliable=false}
 assert(M:SetWatch(81236,150));M.shoppingListMode=true;M.db.settings.filter='81236'
 local rows=M:ShoppingResultRows();assert(#rows==1 and rows[1].floor==123 and rows[1].target==150 and rows[1].status=='SYNCED')
 M.db.settings.filter='No match';assert(#M:ShoppingResultRows()==0)
 M.shoppingListMode=false;reset()
end)
end
