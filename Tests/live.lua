return function(M,check,jobs,advance,emit)
local function new()
 TaliaaTradeBetaDB=nil;VoidMarkMarketDB={};M.jobs={};M:InitializeDatabase();jobs();M.ahOpen=true
end
local function sample(id,floor,at)
 return {itemID=id,marketKey=id,name='Cloth',lastSeen=at,observations=4,confidenceScore=80,volatility=.1,
 fairValue=floor+20,latest={floor=floor,quantity=20},history={{at=at,median=floor}}}
end
local function auction(key,price,id)
 return {auctionID=id or 99,itemKey=key,buyoutAmount=price,quantity=1}
end
check('Live migration removes either legacy mode value without changing finances/history or making a trade',function()
 new();local d=M.db;d.ledger[1]={id=7,kind='posted'};local m=sample(33,111,time());d.market[33]=m
 for _,value in ipairs({true,false}) do d.settings.safeMode=value;M:InitializeDatabase();jobs()
  assert(M.db.settings.safeMode==nil and M.db.market[33]==m and M.db.ledger[1].id==7 and #M.db.ledger==1)
 end
end)
check('Passive tooltip picks exact suffix, level, pet, source, freshness and never starts an AH query',function()
 new();local old=C_Item;C_Item={GetItemInfoInstant=function()return 44,'','', 'INVTYPE_HEAD' end,
 GetDetailedItemLevelInfo=function(link)return link:find('high',1,true) and 19 or 17 end}
 local k=M:Key(44,-2,17,0);local link='|Hitem:44:0:0:0:0:0:-2:0|h[hat]|h'
 M.db.sharedPrices[k]={floor=99,at=time()-30,fair=158,reliable=true}
 local noSearch=M.Search;M.Search=function()error('mouseover queried AH')end
 local lines={};local tip={AddLine=function(_,s)lines[#lines+1]=s end,AddDoubleLine=function(_,a,b)lines[#lines+1]=a..':'..b end}
 M:AppendMarketTooltip(tip,link);local text=table.concat(lines,' ');assert(text:find('Synced account') and text:find('Market estimate') and text:find('99c'))
 assert(not M:TooltipMarketForLink(link:gsub('%-2','-3')))
 assert(not M:TooltipMarketForLink(link:gsub('hat','high')))
 local m=sample(44,101,time());M.db.market[k]=m;assert(M:TooltipMarketForLink(link).floor==101)
 M.db.sharedPrices[k].at=time();assert(M:TooltipMarketForLink(link).source=='Local scan')
 advance(M.db.settings.maxDataAge+1);lines={};M:AppendMarketTooltip(tip,link);assert(table.concat(lines):find('STALE'))
 assert(M:LinkIdentity('|Hbattlepet:500:2:3:100|h[Pet]|h')~=M:LinkIdentity('|Hbattlepet:501:2:3:100|h[Pet]|h'))
 C_Item=old;M.Search=noSearch
end)
check('Clipboard ask transfer carries floors, preserves newer observations and never imports history',function()
 new();local d=M.db;local m=sample(35,91,time());d.market[35]=m;M.marketIndex={35}
 local raw=assert(M:ExportMarketTransfer());assert(raw:find('VMMX2'));new()
 assert(M:ImportMarketTransfer(raw));assert(M.db.sharedPrices[35].floor==91 and not next(M.db.market))
 local old=M.db.sharedPrices[35];old.at=old.at+1
 assert(M:ImportMarketTransfer(raw));assert(M.db.sharedPrices[35]==old)
 assert(not M:ImportMarketTransfer(raw:gsub('Horde','Alliance')))
 local legacy=table.concat({'VMMX1\tTestRealm\tHorde\t'..time()..'\t1','35\t0\t0\t0\t600\t'..time()..'\t42\t1'},'\n')
 assert(M:ImportMarketTransfer(legacy));assert(M.db.sharedPrices[35]==old)
end)
check('Named shopping lists round-trip, preserve local targets, and allow unscanned item IDs',function()
 new();assert(M:SetList('Potion mats'));assert(M:SetWatch(99,50))
 local raw=assert(M:ExportShoppingTransfer());local old=M.db;new()
 assert(M:ImportShoppingTransfer(raw));assert(M:ListBook('Potion mats')[99].target==50);assert(M:SetList('Potion mats'))
 assert(M:SetWatch(99,40));assert(M:ImportShoppingTransfer(raw));assert(M:GetWatchRows()[1].target==40)
 assert(M:SetList('Shopping'));assert(M:SetWatch(99,33));assert(M:ListBook('Potion mats')[99].target==40)
 assert(not M:ImportShoppingTransfer(raw:gsub('99\t0','0\t0')));assert(M:RemoveWatch(99));assert(M:ListBook('Potion mats')[99])
end)
check('Two accounts resume lost data and ACKs after reload; unchanged floors send age only, no financial records',function()
 local oldChat,oldCount,oldFull,oldGroup,oldRaid,oldUnit=C_ChatInfo,GetNumGroupMembers,UnitFullName,IsInGroup,IsInRaid,UnitName
 local endpoints={};local current
 for _,who in ipairs({'Bank','Main'}) do
  new();endpoints[who]={db=M.db,root=M.root,shareRun={},jobs={},name=who,marketIndex={}}
 end
 local function selectClient(name)
  local e=endpoints[name];current=name
  M.db=e.db;M.root=e.root;M.shareRun=e.shareRun;M.jobs=e.jobs;M.marketIndex=e.marketIndex
  M.db.syncPeer=(name=='Bank' and 'main' or 'bank')..'-testrealm';M.shareRegistered=true
 end
 local packets={};local bytes=0;local updates=0
 UnitName=function() return current end;GetNumGroupMembers=function() return 2 end
 UnitFullName=function(unit)if unit=='party1' then return current=='Bank' and 'Main' or 'Bank','TestRealm' end end
 IsInGroup=function()return true end;IsInRaid=function()return false end
 C_ChatInfo={SendAddonMessage=function(prefix,msg,ch)
  assert(#msg<=240);packets[#packets+1]={prefix,msg,ch,current..'-TestRealm',from=current}
  bytes=bytes+#msg;if msg:find('U,',1,true) then updates=updates+1 end
  return 0 end}
 selectClient('Bank');local m=sample(65,109,time());M.db.market[65]=m;M:PublishPrice(m);M.db.ledger={{id=42}}
 assert(M:SetList('Mats'));assert(M:SetWatch(65,200))
 local dropData,dropAck=true,true
 local function step()
  advance(.6)
  for _,who in ipairs({'Bank','Main'}) do selectClient(who);M:PumpSharing() end
  local delivery=packets;packets={}
  for _,v in ipairs(delivery) do
   selectClient(v.from=='Bank' and 'Main' or 'Bank')
   if dropData and v[2]:find('\tD\t',1,true) then dropData=false
   elseif not dropData and dropAck and v.from=='Main' and v[2]:find('\tQ\t',1,true) then dropAck=false
   else M:ReceiveSharing(v[1],v[2],v[3],v[4]) end
  end
 end
 for i=1,70 do step() end
 selectClient('Main');assert(not dropData and not dropAck)
 assert(M.db.sharedPrices[65].floor==109 and #M.db.ledger==0 and not next(M.db.market))
 assert(M:ListBook('Mats')[65].target==200);local seq=M.db.shareReceived['bank-testrealm'].seq
 local previous=M.db.sharedPrices[65];endpoints.Main.shareRun={};selectClient('Main')
 selectClient('Bank');advance(1000);m.lastSeen=time();M:PublishPrice(m);assert(M:SetWatch(65,150))
 for i=1,60 do step() end
 selectClient('Main');assert(updates>0 and M.db.sharedPrices[65].at==m.lastSeen and M:ListBook('Mats')[65].target==150)
 local rx=M.db.shareReceived['bank-testrealm'];assert(rx.seq>seq)
 local bad=M.economyID..'\tD\t'..rx.epoch..'\t'..rx.seq..'\t'..(rx.seq+1)..'\tP,65,'..time()..',1,0;broken'
 local cursor=rx.seq;M:ReceiveSharing('VMMkt2',bad,'PARTY','Bank-TestRealm');assert(rx.seq==cursor)
 M:ReceiveSharing('VMMkt2',bad:gsub(';broken',''),'PARTY','Stranger-TestRealm');assert(rx.seq==cursor)
 M:ReceiveSharing('VMMkt2',bad:gsub(';broken',''):gsub('Horde','Alliance'),'PARTY','Bank-TestRealm');assert(rx.seq==cursor)
 selectClient('Bank');assert(M:RemoveWatch(65));for i=1,25 do step() end
 selectClient('Main');assert(not M:ListBook('Mats')[65]);assert(bytes<14000)
 C_ChatInfo=oldChat;GetNumGroupMembers=oldCount;UnitFullName=oldFull;IsInGroup=oldGroup;IsInRaid=oldRaid;UnitName=oldUnit
 new()
end)
check('Posting rechecks slot, quantity, live quote, deposit and requires a confirm click',function()
 new();M.view='selling';local A=C_AuctionHouse;local old=A;local api=setmetatable({},{__index=A});C_AuctionHouse=api
 local loc,con,ask=ItemLocation,C_Container,M.AskTrade
 local row={bag=0,slot=1,itemID=33,itemLink='test',name='Test',quantity=4};M.selectedRow=row
 local bag={itemID=33,hyperlink='test',stackCount=4};local k={itemID=33,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0}
 ItemLocation={CreateFromBagAndSlot=function()return {} end};C_Container={GetContainerItemInfo=function()return bag end}
 api.GetItemKeyFromItem=function()return k end;api.GetAvailablePostCount=function()return 4 end
 local com=false;api.GetItemKeyInfo=function()return {isCommodity=com} end
 local deposit=10;api.CalculateItemDeposit=function()return deposit end;api.CalculateCommodityDeposit=api.CalculateItemDeposit
 local confirms,posts=0,0;local callback
 M.AskTrade=function(_,msg,cb)callback=cb;confirms=confirms+1 end
 api.PostItem=function(_,d,n,bid,unit)assert(d==2 and n==3 and bid==nil and unit==100);posts=posts+1;return false end
 api.PostCommodity=function(_,d,n,unit)assert(d==2 and n==3 and unit==100);posts=posts+1;return false end
 local function quote()M.postQuote={row=row,k=k,at=GetTime(),floor=105};callback=nil end
 quote();M:ReviewPost(row,5,100,2);assert(not callback)
 quote();M:ReviewPost(row,3,100,2);assert(confirms==1 and posts==0);bag.hyperlink='moved';callback();assert(posts==0)
 bag.hyperlink='test';quote();M:ReviewPost(row,3,100,2);deposit=20;callback();assert(posts==0)
 for _,v in ipairs({false,true}) do com=v;quote();M:ReviewPost(row,3,100,2);assert(callback);callback();callback()
  assert(M.tradePending=='post');emit('AUCTION_HOUSE_AUCTION_CREATED',85)
 end
 assert(posts==2);quote();advance(16);M:ReviewPost(row,3,100,2);assert(not callback)
 C_AuctionHouse=old;ItemLocation=loc;C_Container=con;M.AskTrade=ask
end)
check('Cancellation validates exact ownership and fee again after confirmation',function()
 new();local old=C_AuctionHouse;C_AuctionHouse=setmetatable({},{__index=old})
 local k={itemID=33};local row={auctionID=99,itemKey=k,quantity=1,name='Item'};local items={auction(k,101)}
 local fee,cancels=0,0;C_AuctionHouse.GetOwnedAuctions=function()return items end
 C_AuctionHouse.GetCancelCost=function()return fee end;C_AuctionHouse.CanCancelAuction=function()return true end
 C_AuctionHouse.CancelAuction=function(id)assert(id==99);cancels=cancels+1 end
 local ask=M.AskTrade;local cb;M.AskTrade=function(_,_,f)cb=f end
 M.view='my auctions';M.selectedRow=row;M:ReviewCancel(row);assert(cb and cancels==0);fee=10;cb();assert(cancels==0)
 M:ReviewCancel(row);items={};cb();assert(cancels==0)
 items={auction(k,101)};M:ReviewCancel(row);cb();cb();assert(cancels==1)
 emit('AUCTION_CANCELED',99);C_AuctionHouse=old;M.AskTrade=ask
end)
check('Manual shopping does not require investment ROI but still blocks unaffordable or over-limit purchases',function()
 new();local m=sample(33,100,time());m.observations=0;m.fairValue=0
 local e=M:Economics(m,100,1,'shopping');assert(e.net<0 and M:CheckRisk(m,e))
 M.db.settings.minGoldReserve=GetMoney();assert(not M:CheckRisk(m,e))
 M.db.settings.minGoldReserve=0;M.db.settings.maxTransaction=99;assert(not M:CheckRisk(m,e))
end)
check('Live name search returns a new unscanned variant and admits it to shopping review without buying',function()
 new();M.view='browse';M.db.settings.filter='Linen';M.queue.nextSend=0
 local orig=C_AuctionHouse.GetBrowseResults;C_AuctionHouse.GetBrowseResults=function()
  return {{itemKey={itemID=60,itemSuffix=-3,itemLevel=12},minPrice=43}}
 end
 M:LiveNameSearch('Linen');M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');jobs()
 local row=M.browseRows[1];assert(row and row.floor==43 and row.marketKey==M:Key(60,-3,12))
 M:ShopSelected(row);assert(M.execution.state=='selected' and M.execution.market.itemLevel==12 and not next(M.db.pending))
 C_AuctionHouse.GetBrowseResults=orig
end)
check('Nexus import accepts the current character and complete learned recipes only',function()
 new();local old=VoidMarkNexus;local r={name='Potion',learned=true,spell=1,output=42,outputMin=1,outputMax=1,reagents={{id=5,qty=3}}}
 VoidMarkNexus={economy='Other|Horde',character={name=UnitName('player'),professions={{name='Alchemy',recipes={r}}}}}
 assert(not M:ReadNexusRecipes());VoidMarkNexus.economy=M.economyID
 assert(M:ReadNexusRecipes());jobs();assert(M:KnownRecipe(M.db.recipes['spell:1']) and M.db.recipes['spell:1'].reagents[1].quantity==3)
 r.spell=2;r.incomplete=true;assert(M:ReadNexusRecipes());jobs();assert(not M.db.recipes['spell:2'])
 VoidMarkNexus=old
end)
check('Live sharing pauses in lockdown and only whispers an online paired character friend',function()
 new();local old=C_ChatInfo;local friend=C_FriendList;local num=GetNumGroupMembers
 local lockdown=true;local online=true;local n=0
 GetNumGroupMembers=function()return 0 end
 C_ChatInfo={RegisterAddonMessagePrefix=function()return 0 end,InChatMessagingLockdown=function() return lockdown end,
 SendAddonMessage=function(_,msg,ch,target)assert(ch=='WHISPER' and target=='bank-testrealm' and #msg<=240);n=n+1;return 0 end}
 C_FriendList={GetFriendInfo=function()return {name='Bank',connected=online} end}
 M:PairPeer('Bank-TestRealm');M:PumpSharing();assert(n==0)
 lockdown=false;advance(6);M:PumpSharing();assert(n==1)
 online=false;advance(25);M:PumpSharing();assert(n==1)
 M:PairPeer('off');C_ChatInfo=old;C_FriendList=friend;GetNumGroupMembers=num
end)
check('Clipboard paging covers 1,500 exact keys without copying transaction records',function()
 new();local source=M.db;M.marketIndex={}
 for i=1,1500 do M.db.market[i]=sample(i,i+10,time());M.marketIndex[i]=i end
 local pages={};for i=1,15 do local raw,err,page,total=M:ExportMarketTransfer(i);assert(raw and page==i and total==15,err);pages[i]=raw end
 new();for _,raw in ipairs(pages) do assert(M:ImportMarketTransfer(raw)) end
 for i=1,1500 do assert(M.db.sharedPrices[i].floor==i+10) end
 assert(not next(M.db.market) and not next(M.db.ledger));assert(#source.market==1500)
end)
check('A newer simple ask does not erase a reliable earlier historical estimate',function()
 new();local k=22;local old={key=k,floor=100,at=time(),fair=115,reliable=true}
 M:MergeAsk(old);advance(5);M:MergeAsk({key=k,floor=90,at=time()})
 local p=M:PriceObservation(k);assert(p.floor==90 and p.fair==115)
 M:MergeAsk({key=k,at=time()-10,floor=5});assert(M:PriceObservation(k).floor==90)
end)
check('A completed full scan publishes batched asks without transferring scan history or duplicating observations',function()
 new();local d=M.db;d.syncPeer='bank-testrealm'
 M:StartSnapshotProcessing(3000,'fresh replicate request');jobs()
 assert(d.latestScan.uniqueItems>=1400 and d.latestScan.auctionsProcessed>2900 and not M.scanState.running)
 local m=d.market[1];assert(m and M:PriceObservation(1).floor==m.latest.floor)
 local j=d.shareJournal;assert(j.latest.P1 and j.rows[j.latest.P1]:find('P,1,',1,true))
 local seq=j.seq;M:QueueScanSharing(d.lastDepthSnapshotAt);jobs();assert(j.seq==seq)
 local seen=m.lastSeen;local history=#m.history
 M:StartSnapshotProcessing(3000,'cached snapshot');jobs();assert(m.lastSeen==seen and #m.history==history and j.seq==seq)
end)
end
