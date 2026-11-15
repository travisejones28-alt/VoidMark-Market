return function(M,check,jobs,advance,emit)
check('1.23.30 bank sync sends only real price moves, not every re-estimate',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs();M:PairPeer('Bank');jobs()
 local S=M.SameSharedPrice
 assert(S(1000,2000,60,1005,2050,65),'tiny moves are the same price')
 assert(not S(1000,2000,60,1020,2000,60),'floor 2% move is sent')
 assert(S(3,0,0,4,0,0),'1 copper on a 3c item is noise')
 assert(not S(3,0,0,5,0,0),'2 copper on a 3c item is sent')
 assert(not S(1000,2000,60,1000,2200,60),'estimate 10% move is sent')
 assert(not S(1000,0,60,1000,2000,60),'a new estimate is sent')
 assert(not S(1000,2000,60,1000,2000,75),'confidence 15 points is sent')
 assert(not S(nil,nil,nil,1,0,0),'first price is sent')
 local m={marketKey=81240,itemID=81240,name='Thing',lastSeen=time(),latest={floor=1000},confidenceScore=60,fairValue=2000}
 M.CanEstimateResale=function() return true end
 M.db.market[81240]=m;M.marketIndex={81240}
 M:PublishPrice(m);local j=M.db.shareJournal;local seq=j.seq
 advance(60);m.lastSeen=time();m.latest.floor=1004;m.fairValue=2030;M:PublishPrice(m)
 assert(j.seq==seq,'a re-estimate inside the bands queued a row')
 advance(60);m.lastSeen=time();m.latest.floor=900;M:PublishPrice(m)
 assert(j.seq==seq+1 and j.rows[j.seq]:find(',900,',1,true),'a 10% floor drop was not sent')
end)
check('1.23.31 prices go to the partner only when asked (theirs over an hour old); list edits go at once',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 M.db.lastDepthSnapshotAt=time();M.db.syncLastReceivedCompleteAt=nil
 local rx={epoch='1-2',seq=10,total=50,scanAt=time()}
 assert(not M:SyncShouldAsk(rx),'own scan is fresh: no ask')
 advance(3700)
 assert(not M:SyncShouldAsk(rx),'partner scan not newer than ours: no ask')
 rx.scanAt=time()
 assert(M:SyncShouldAsk(rx),'ours over an hour old, theirs newer: ask')
 rx.seq=50;assert(not M:SyncShouldAsk(rx),'already have everything: no ask')
 M.db.syncLastReceivedCompleteAt=time();rx.seq=10;assert(not M:SyncShouldAsk(rx),'complete set received recently: no ask')
 -- Journal: price rows are not urgent, list rows are.
 local j=M.db.shareJournal
 M:Journal('Pk','P,1,1,1,0,0');assert(not j.urgentSeq)
 M:Journal('Lk','L,Mats,65,200');assert(j.urgentSeq==j.seq)
end)
check('1.23.32 a sale knows the price you posted at, even unopened Listings and suffix items',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 M.ownedRows={};M.saleClaimed={}
 -- Posted with Market: the created event saves it as a listing at once.
 local row={marketKey=15284,name='Crusader Bow',link='|cff1eff00|Hitem:15284::::::1027|h[Crusader Bow of the Bandit]|h|r',postedUnit=10000,postedQuantity=1,postKey=15284}
 M.postingRow=row
 emit('AUCTION_HOUSE_AUCTION_CREATED',4242)
 local a=M:BuildSaleAlert('Crusader Bow of the Bandit',nil,nil)
 assert(a.gross==10000 and not a.estimate,'sale used the market price, not the post: '..tostring(a.gross or a.unit))
 -- Suffix key shared by several suffixes: the post of this exact name wins.
 M.db.ownedSnapshot=nil;M.ownedRows={};M.saleClaimed={}
 local link='|cff1eff00|Hitem:15284::::::1027|h[Crusader Bow of the Bandit]|h|r'
 local k=M:LinkIdentity(link);assert(k~=nil,'no key from link')
 M.db.market[k]={name='Crusader Bow',mixedVariants=true,latest={floor=12900}}
 M.db.postHistory={[k]={{at=time(),unit=9000,quantity=1,name='Crusader Bow of the Eagle'},{at=time()-60,unit=10000,quantity=1,name='Crusader Bow of the Bandit'}}}
 a=M:BuildSaleAlert('Crusader Bow of the Bandit',nil,'|cff1eff00|Hitem:15284::::::1027|h[Crusader Bow of the Bandit]|h|r')
 assert(a.gross==10000 and not a.estimate,'suffix post not matched by name: '..tostring(a.gross or a.unit))
end)
check('1.23.32 Selling re-checks a picked item by itself instead of waiting on Refresh',function()
 local calls=0;local old=M.CheckPost
 M.CheckPost=function(self,row) calls=calls+1 end
 local row={bag=0,slot=1,name='Mystic Heavy Armor Kit'}
 M.selectedRow=row;M.postQuote=nil;M.ahOpen=true;M.view='selling';M.tradePending=nil;M.sellCheckAt=nil;M.sellAutoRow=nil
 M:SellTick();assert(calls==0,'checked before the short wait')
 advance(0.6);M:SellTick();assert(calls==1,'no automatic check')
 advance(1);M:SellTick();assert(calls==1,'checked again too soon')
 advance(1.1);M:SellTick();assert(calls==2,'no second check')
 M.postQuote={row=row};advance(3);M:SellTick();assert(calls==2,'re-checked while a check is running')
 M.postQuote=nil;for i=1,30 do advance(2.1);M:SellTick() end
 assert(calls<=15,'kept checking forever: '..calls)
 M.CheckPost=old;M.selectedRow=nil;M.ahOpen=nil;M.view=nil;M.sellAutoRow=nil
end)
end