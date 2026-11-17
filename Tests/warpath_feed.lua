return function(M,check,jobs,advance,emit)
local function as(name)
 NameUtil=nil;UnitNameUnmodified=nil;UnitName=function() return name end
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
end
local function copy(t) if type(t)~='table' then return t end local o={};for k,v in pairs(t) do o[k]=copy(v) end;return o end
local oldName,oldNU,oldUNU=UnitName,NameUtil,UnitNameUnmodified

check('1.24.0 Warpath feed: logout writes the journal, partner applies it and the sync jumps ahead',function()
 as('Voidmark Bank');assert(M.db.syncPeer=='voidmark soulreaver-testrealm')
 local now=time()
 M:Journal('P14047','P,14047,'..now..',2500,3000,80')
 M:Journal('P2589','P,2589,'..(now-10)..',40,55,70')
 M:Journal('P2589','P,2589,'..now..',45,55,70') -- replaces the older row
 M:Journal('U14047','U,14047,'..now..','..now)
 M:Journal('WShopping/14047','W,Shopping,14047,'..now..',2000,voidmark bank')
 M.db.latestScan={completedAt=now-60,auctionsProcessed=204122}
 -- A scan still being published when the bank reloads is finished first.
 local ran=false
 M:AddJob('share-scan',function(start) if debugprofilestop()-start>=3 then return false end;ran=true;M:Journal('P2592','P,2592,'..now..',900,1000,60');return true end)
 VoidMarkMarketFeedOut=nil;emit('PLAYER_LOGOUT')
 local out=VoidMarkMarketFeedOut
 assert(ran and not M.jobs['share-scan'],'pending scan publish flushed')
 assert(out and out.version==1 and out.character=='Voidmark Bank' and out.economy==M.economyID)
 assert(out.seq==M.db.shareJournal.seq and #out.rows==5,'latest row per key only: '..#out.rows)
 assert(out.rows[#out.rows]:match('^P,2592,'),'rows in journal order')
 assert(out.scanAt==now-60 and out.auctions==204122)

 -- Warpath copies it (plus an unrelated character's and another realm's copy).
 local other=copy(out);other.character='Someone Else';other.savedAt=out.savedAt+5
 local realm=copy(out);realm.economy='OtherRealm|Horde';realm.savedAt=out.savedAt+9
 VoidMarkMarket_WarpathFeeds={copy(out),other,realm}

 as('Voidmark Soulreaver');assert(M.db.syncPeer=='voidmark bank-testrealm')
 assert(not M.db.sharedPrices[14047])
 M.shareRun.lastContact=GetTime()
 M:ImportWarpathFeed();assert(M:SimpleSyncStatus()=='Bank sync: loading Warpath copy');jobs()
 local p=M.db.sharedPrices[14047];assert(p and p.floor==2500 and p.fair==3000,'price applied')
 assert(M.db.sharedPrices[2589].floor==45 and M.db.sharedPrices[2592].floor==900)
 assert(M.db.watchlist[14047] and M.db.watchlist[14047].target==2000,'list change applied')
 local rx=M.db.shareReceived[M.db.syncPeer]
 assert(rx.epoch==out.epoch and rx.seq==out.seq and rx.total==out.seq,'sync jumps to the file point')
 assert(M.shareRun.reply=='Q\t'..out.epoch..'\t'..out.seq,'partner told to skip what the file carried')
 assert(M:SimpleScanStatus():find('by Voidmark Bank',1,true) and M:SimpleScanStatus():find('204122 auctions',1,true),M:SimpleScanStatus())
 -- Loading the same copy again does nothing; sync pages already covered are acknowledged.
 M:ImportWarpathFeed();assert(not M.jobs['warpath-feed'])
 local prefix=M.economyID..'\t'
 M:ReceiveSharing('VMMkt2',prefix..table.concat({'D',out.epoch,0,1,'P,2589,'..now..',1,0'},'\t'),'WHISPER','Voidmark Bank-TestRealm')
 assert(M.db.sharedPrices[2589].floor==45,'old page ignored')
 VoidMarkMarket_WarpathFeeds=nil;VoidMarkMarketFeedOut=nil
end)

check('1.24.0 Warpath feed ignores copies from yourself, other realms and broken files',function()
 as('Voidmark Soulreaver')
 VoidMarkMarket_WarpathFeeds={{version=1,economy=M.economyID,character='Voidmark Soulreaver',epoch='1-1',seq=1,savedAt=time(),rows={'P,7,'..time()..',5,0,0'}},
  {version=1,economy='Else|Alliance',character='Voidmark Bank',epoch='1-1',seq=1,savedAt=time(),rows={'P,8,'..time()..',5,0,0'}},
  {version=1,economy=M.economyID,character='Voidmark Bank',epoch='1-1',seq='x',savedAt=time(),rows={}},
  'junk'}
 M:ImportWarpathFeed();jobs();assert(not M.db.sharedPrices[7] and not M.db.sharedPrices[8])
 -- A bad row is skipped, the rest still load.
 VoidMarkMarket_WarpathFeeds={{version=1,economy=M.economyID,character='Voidmark Bank',epoch='2-2',seq=3,savedAt=time(),rows={'P,9,'..time()..',5,0,0','garbage',42}}}
 M:ImportWarpathFeed();jobs();assert(M.db.sharedPrices[9] and M.db.warpathFeed.skipped==2)
 VoidMarkMarket_WarpathFeeds=nil
end)

check('1.24.0 first scan of the day offers the save reload once',function()
 as('Voidmark Bank');local shown=0;local oldShow=StaticPopup_Show
 StaticPopup_Show=function(n) if n=='VOIDMARKMARKET_FEEDSAVE' then shown=shown+1 end end
 M:QueueScanSharing(time());jobs();assert(shown==1,'after the scan finishes publishing')
 M:QueueScanSharing(time());jobs();assert(shown==1,'once a day')
 M.db.feedPromptDay='2000-01-01';InCombatLockdown=function() return true end
 M:QueueScanSharing(time());jobs();assert(shown==1 and M.feedPromptPending,'waits for combat to end')
 InCombatLockdown=function() return false end;emit('PLAYER_REGEN_ENABLED');assert(shown==2)
 -- Flushing at logout never pops it up.
 M.db.feedPromptDay='2000-01-01';M:QueueScanSharing(time());emit('PLAYER_LOGOUT');assert(shown==2)
 StaticPopup_Show=oldShow;InCombatLockdown=nil;VoidMarkMarketFeedOut=nil
end)

check('1.24.0 the remembered search runs on its own after a reload',function()
 as('Voidmark Soulreaver')
 M.db.sharedPrices['14047']=nil
 M.db.itemNames[14047]='Runecloth'
 M.db.sharedPrices[14047]={id=14047,floor=2500,fair=3000,at=time(),reliable=true}
 M.db.settings.filter='runecloth';M.browseRows=nil;M.shoppingListMode=false;M.snipeView=false
 local gii=GetItemInfo;GetItemInfo=function() end
 M:ShoppingResultRows();jobs()
 local rows=M:ShoppingResultRows();assert(#rows==1 and rows[1].name=='Runecloth',#rows)
 GetItemInfo=gii;M.db.settings.filter=''
end)

UnitName,NameUtil,UnitNameUnmodified=oldName,oldNU,oldUNU
VoidMarkMarketDB={};M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
end
