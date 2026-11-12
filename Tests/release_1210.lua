return function(M,check,jobs,advance,emit)
-- 1.21 fast bank sync: lanes, packed pages, out-of-order delivery.
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M.shareLanes=nil;M:InitializeDatabase();jobs()
end
local P=M.SyncPack

check('1.21 packed rows round-trip exactly, including literal "!" fields and leading zeros',function()
 local base=time()-8000000
 for _,line in ipairs({'P,4242,'..time()..',77,0,0','P,1234:s-10,'..time()..',1500,1400,55','U,9100,'..(time()-60)..','..time(),
  'W,My%20List,65,'..time()..',200,voidmark%20bank','W,!odd,65,'..time()..',-1,!x','P,65,'..(time()-100*86400)..',007,0,0'}) do
  local packed=P.pack(line,base);assert(P.unpack(packed,base)==line,line..' -> '..packed..' -> '..tostring(P.unpack(packed,base)))
 end
 -- Real-world sizes: a 10-digit timestamp becomes a short offset.
 local now=1794497000;local line='P,1234:s-10,'..now..',150000,140000,55'
 local packed=P.pack(line,now-8000000)
 assert(#packed<=#line-8 and packed:find('!^',1,true) and P.unpack(packed,now-8000000)==line,'meaningfully shorter: '..packed)
 assert(#P.hash('CAMWOW US2 Realm 8 PvP|Horde')==5 and P.hash('CAMWOW US2 Realm 8 PvP|Horde')==P.hash('camwowus2realm8pvp|horde'))
 assert(P.unb62(P.b62(1794497000))==1794497000 and P.unb62('!')==nil)
end)

check('1.21 packed mode: only after the partner says so; pages spread over lanes and carry more rows, same total budget',function()
 local old=C_ChatInfo;local sent={}
 C_ChatInfo={RegisterAddonMessagePrefix=function() return 0 end,SendAddonMessage=function(prefix,msg) sent[#sent+1]={prefix,msg};assert(#msg<=240);return 0 end}
 local ok,err=pcall(function()
  reset();M:PairPeer('Bank');jobs()
  local j=M.db.shareJournal;local r=M.shareRun
  assert(#M.shareLanes==4,'four lanes registered')
  j.seq=0;j.rows={};j.latest={}
  for i=1,300 do j.seq=i;j.rows[i]='P,'..(50000+i)..':s-10,'..time()..','..(10000+i)..',9000,50' end
  M.shareRegistered=true;r.lastContact=GetTime();r.hello=GetTime()+100;r.cursor=0;r.next=0
  M:PumpSharing();local legacy=sent[1][2];assert(legacy:find('\tD\t',1,true),'standard pages until the partner opts in')
  local legacyRows=select(2,legacy:gsub(';',''))+1
  -- Partner says it understands fast pages on 4 lanes.
  sent={};r.cursor=0;r.sentHi=nil;r.pages=nil;r.next=0
  M:ReceiveSharing('VMMkt2',M.economyID..'\tC\t'..j.epoch..'\t3\t4','WHISPER','Bank-TestRealm')
  assert(r.peerV3 and r.peerLanes==4)
  M:PumpSharing()
  local prefixes={};local fastRows=0
  for _,m in ipairs(sent) do prefixes[m[1]]=true;assert(m[2]:find('^#%w+\tE\t'),m[2]:sub(1,30)) end
  local n=0;for _ in pairs(prefixes) do n=n+1 end
  assert(n==4,'all four lanes used: '..n)
  fastRows=select(2,sent[1][2]:gsub(';',''))+1
  assert(fastRows>=legacyRows*1.5,'more rows per message: '..fastRows..' vs '..legacyRows)
  -- 1.22.4: never more traffic than the old single-lane budget (the server
  -- disconnects a character that floods addon messages).
  local bytes=0;for _,m in ipairs(sent) do bytes=bytes+#m[2]+1 end
  assert(#sent<=8 and bytes<=3000,'same budget as before: '..#sent..' msgs, '..bytes..' bytes')
  r.next=0;M:PumpSharing();assert(#sent<=8,'window full: no more until acknowledged')
  -- A throttled send pauses everything briefly; that lane waits longer.
  sent={};local throttled
  C_ChatInfo.SendAddonMessage=function(prefix,msg) if not throttled then throttled=prefix;return 3 end;sent[#sent+1]={prefix,msg};return 0 end
  M:ReceiveSharing('VMMkt2',M.economyID..'\tQ\t'..j.epoch..'\t'..r.sentHi,'WHISPER','Bank-TestRealm')
  advance(3);r.next=0;M:PumpSharing()
  assert(throttled and #sent==0 and r.throttleUntil>GetTime(),'backs off after a refusal')
  advance(2);r.next=0;M:PumpSharing()
  assert(#sent>0,'resumes');for _,m in ipairs(sent) do assert(m[1]~=throttled,'refused lane rests longer') end
 end)
 C_ChatInfo=old;M.shareLanes=nil;if not ok then error(err,0) end
end)

check('1.21 receiver: fast pages applied in order even when lanes deliver them out of order',function()
 reset();M:PairPeer('Bank');local peer='Bank-TestRealm';local epoch='7-77'
 M:ReceiveSharing('VMMkt2','TestRealm|Horde\tH\t'..epoch,'WHISPER',peer)
 local base=time()-8000000;local b=P.b62(base);local h='#'..P.hash(M.economyID)
 local function page(lo,hi,price) return h..'\tE\t'..epoch..'\t'..lo..'\t'..hi..'\t'..b..'\t'..P.pack('P,'..(9200+hi)..','..time()..','..price..',0,0',base) end
 -- Pages 2 and 3 arrive before page 1 (on other lanes).
 M:ReceiveSharing('VMMkt2c',page(2,3,300),'WHISPER',peer)
 M:ReceiveSharing('VMMkt2b',page(1,2,200),'WHISPER',peer)
 local rx=M.db.shareReceived[M.db.syncPeer];assert(rx.seq==0,'held until the gap is filled')
 M:ReceiveSharing('VMMkt2',page(0,1,100),'WHISPER',peer)
 assert(rx.seq==3,'all three applied: '..rx.seq)
 assert(M.db.sharedPrices[9201].floor==100 and M.db.sharedPrices[9202].floor==200 and M.db.sharedPrices[9203].floor==300)
 assert(M.shareRun.reply:find('Q\t'..epoch..'\t3',1,true),'acknowledges the whole run')
 -- A duplicate is acknowledged, not applied twice; a wrong economy hash is rejected.
 M:ReceiveSharing('VMMkt2d',page(1,2,999),'WHISPER',peer);assert(M.db.sharedPrices[9202].floor==200)
 M:ReceiveSharing('VMMkt2',('#zzzzz')..'\tE\t'..epoch..'\t3\t4\t'..b..'\tP,9300,'..time()..',5,0,0','WHISPER',peer);assert(rx.seq==3)
 -- Unknown prefixes are ignored.
 M:ReceiveSharing('Other',page(3,4,400),'WHISPER',peer);assert(rx.seq==3)
end)

check('1.22 Sale alert: coin sound, on-screen message with price and flip profit, sent to the partner',function()
 local old=C_ChatInfo;local sent={}
 C_ChatInfo={RegisterAddonMessagePrefix=function() return 0 end,SendAddonMessage=function(prefix,msg) sent[#sent+1]={prefix,msg};return 0 end}
 local oldSound,oldRaid,oldFrame=PlaySound,RaidNotice_AddMessage,RaidWarningFrame
 local sounds,notices=0,{}
 PlaySound=function() sounds=sounds+1 end;RaidWarningFrame={};RaidNotice_AddMessage=function(_,t) notices[#notices+1]=t end
 local ok,err=pcall(function()
  reset();M:PairPeer('Bank');jobs()
  M.db.flips={};M:RecordFlipBuy({name='Lupine Vest of Agility',quantity=1,cost=1400})
  M.ownedRows={{auctionID=11,name='Lupine Vest',unit=4900,quantity=1,status=0}} -- base name on the listing
  emit('CHAT_MSG_SYSTEM','A buyer has been found for your auction of Lupine Vest of Agility.')
  assert(sounds==1 and #notices==1,'sound + on-screen')
  local t=notices[1]
  assert(t:find(M:Coins(4900),1,true) and t:find(M:Coins(4655),1,true) and t:find('+'..M:Coins(3255),1,true),t)
  -- Sent to the partner once contact is up.
  local r=M.shareRun;M.shareRegistered=true;r.lastContact=GetTime();r.hello=GetTime()+100;r.next=0
  M:PumpSharing()
  local msg;for _,m in ipairs(sent) do if m[2]:find('\tN\t',1,true) then msg=m[2] end end
  assert(msg and #msg<=240,'alert sent')
  -- Partner side: shown with who sold it; a repeat is ignored.
  notices={};sounds=0
  M:ReceiveSharing('VMMkt2',msg,'WHISPER','Bank-TestRealm')
  assert(#notices==1 and notices[1]:find('Bank:',1,true) and notices[1]:find('flipped for',1,true),notices[1] or 'none')
  M:ReceiveSharing('VMMkt2',msg,'WHISPER','Bank-TestRealm');assert(#notices==1,'no duplicate')
  -- Unknown listing and no buy: still alerts, without numbers.
  notices={};M.ownedRows={}
  emit('CHAT_MSG_SYSTEM','A buyer has been found for your auction of Mystery Cloak.')
  assert(notices[1]:find('price shows when the mail arrives',1,true))
  -- Off switches.
  notices={};sounds=0;SlashCmdList.VOIDMARKMARKET('salesound off')
  emit('CHAT_MSG_SYSTEM','A buyer has been found for your auction of Mystery Cloak.');assert(sounds==0 and #notices==1)
  SlashCmdList.VOIDMARKMARKET('salealerts off');notices={}
  emit('CHAT_MSG_SYSTEM','A buyer has been found for your auction of Mystery Cloak.');assert(#notices==0)
  SlashCmdList.VOIDMARKMARKET('salealerts on');SlashCmdList.VOIDMARKMARKET('salesound on')
  assert(not M:HandleAuctionSold('Some other system message'))
 end)
 C_ChatInfo=old;PlaySound,RaidNotice_AddMessage,RaidWarningFrame=oldSound,oldRaid,oldFrame;M.db.flips={};M.ownedRows=nil
 if not ok then error(err,0) end
end)

check('1.22.1 Settings has checkboxes for sale alerts, coin sound, sending to partner and the paid floor',function()
 M:InitializeUI();M:SetView('settings');M:RenderUI()
 local byKey={};for _,c in ipairs(M.flipToggles) do byKey[c.key]=c end
 for _,k in ipairs({'saleAlerts','saleAlertSound','saleAlertsShare','sellNeverBelowPaid'}) do assert(byKey[k] and byKey[k]:GetChecked(),k..' on by default') end
 byKey.saleAlertSound:SetChecked(false);byKey.saleAlertSound.scripts.OnClick(byKey.saleAlertSound)
 assert(M.db.settings.saleAlertSound==false)
 byKey.sellNeverBelowPaid:SetChecked(false);byKey.sellNeverBelowPaid.scripts.OnClick(byKey.sellNeverBelowPaid)
 assert(M.db.settings.sellNeverBelowPaid==false)
 M:RenderUI();assert(not byKey.saleAlertSound:GetChecked(),'reflects saved setting')
 SlashCmdList.VOIDMARKMARKET('salesound on');M:RenderUI();assert(byKey.saleAlertSound:GetChecked(),'slash and checkbox agree')
 M.db.settings.sellNeverBelowPaid=true;M:SetView('browse')
end)

check('1.22.2 Tooltip: an item missing from the latest full scan says "none listed now" instead of just "14h old"',function()
 local key=M:Key(1070);local lines={}
 local tip={AddDoubleLine=function(_,l,r) lines[#lines+1]=l..'='..r end,AddLine=function() end}
 local oldLink=M.LinkIdentity;M.LinkIdentity=function() return key end
 M.db.market[key]={itemID=1070,marketKey=key,lastSeen=time()-14*3600,latest={floor=3200}}
 local oldScan=M.db.latestScan
 M.db.latestScan={completedAt=time()-20*60}
 M:AppendMarketTooltip(tip,'|Hitem:1070|h[x]|h')
 assert(lines[#lines]:find('none listed now, last seen 14h ago',1,true) and lines[#lines]:find(M:Coins(3200),1,true),lines[#lines])
 -- Seen in the latest scan: normal line.
 lines={};M.db.market[key].lastSeen=time()-20*60;M:AppendMarketTooltip(tip,'|Hitem:1070|h[x]|h')
 assert(not lines[#lines]:find('none listed',1,true),lines[#lines])
 -- The partner's newer scan counts too.
 lines={};M.db.market[key].lastSeen=time()-14*3600;M.db.latestScan={completedAt=time()-30*3600}
 M.db.syncPeer='bank';M.db.shareReceived={bank={scanAt=time()-600}}
 M:AppendMarketTooltip(tip,'|Hitem:1070|h[x]|h');assert(lines[#lines]:find('none listed now',1,true))
 M.db.market[key]=nil;M.db.latestScan=oldScan;M.LinkIdentity=oldLink;M.db.syncPeer=nil;M.db.shareReceived={}
end)

check('1.22.6 Forever AH notifications: a sale (with its auction ID) alerts and relays; a win records the buy',function()
 local old=C_ChatInfo;local sent={}
 C_ChatInfo={RegisterAddonMessagePrefix=function() return 0 end,SendAddonMessage=function(prefix,msg) sent[#sent+1]={prefix,msg};return 0 end}
 local oldSound,oldRaid,oldFrame=PlaySound,RaidNotice_AddMessage,RaidWarningFrame
 local notices={};PlaySound=function() end;RaidWarningFrame={};RaidNotice_AddMessage=function(_,t) notices[#notices+1]=t end
 local ok,err=pcall(function()
  reset();M:PairPeer('Bank');jobs();M.db.flips={}
  M:RecordFlipBuy({name='Twilight Cuffs of the Physician',quantity=1,cost=2200})
  M:RecordFlipBuy({name='Twilight Cuffs of the Physician',quantity=1,cost=1000})
  M.ownedRows={{auctionID=501,name='Twilight Cuffs',unit=5000,quantity=1,status=0},{auctionID=502,name='Twilight Cuffs',unit=3500,quantity=1,status=0}}
  -- The exact auction (502, 35s) sold: the price comes from that auction, not the first match.
  emit('AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION',4,'|cff1eff00|Hitem:1:0|h[Twilight Cuffs of the Physician]|h|r',502)
  assert(#notices==1 and notices[1]:find(M:Coins(3500),1,true),notices[1] or 'none')
  -- The chat echo of the same sale is not counted again.
  emit('CHAT_MSG_SYSTEM','A buyer has been found for your auction of Twilight Cuffs of the Physician.')
  assert(#notices==1,'no double alert')
  -- Relayed to the partner.
  local r=M.shareRun;M.shareRegistered=true;r.lastContact=GetTime();r.hello=GetTime()+100;r.next=0;M:PumpSharing()
  local relayed=false;for _,m in ipairs(sent) do if m[2]:find('\tN\t',1,true) then relayed=true end end
  assert(relayed,'sent to the main')
  -- Two real sales of the same item from the AH both alert.
  notices={}
  emit('AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION',4,'Twilight Cuffs of the Physician',501)
  assert(#notices==1 and notices[1]:find(M:Coins(5000),1,true))
  -- A win on the normal AH is recorded from the notification + the bid sent.
  M.execution={state='idle'};M:NoteOutsideBid(900,1234)
  emit('AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION',2,'[Superior Belt of Agility]',900)
  local found;for _,f in ipairs(M:FlipBook()) do if f.name=='Superior Belt of Agility' then found=f end end
  assert(found and found.cost==1234,'won buy recorded')
  emit('CHAT_MSG_SYSTEM','You won an auction for Superior Belt of Agility')
  local n=0;for _,f in ipairs(M:FlipBook()) do if f.name=='Superior Belt of Agility' then n=n+1 end end
  assert(n==1,'chat echo of the win not recorded twice')
  -- Other notifications are ignored.
  assert(not M:HandleAHNotification(0,'Something',1))
 end)
 C_ChatInfo=old;PlaySound,RaidNotice_AddMessage,RaidWarningFrame=oldSound,oldRaid,oldFrame;M.db.flips={};M.ownedRows=nil
 if not ok then error(err,0) end
end)
end
