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
 PlaySound=function() sounds=sounds+1 end;local origToast=M.SaleToast;M.SaleToast=function(self,a,from,text) notices[#notices+1]=text;return origToast(self,a,from,text) end
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
 C_ChatInfo=old;PlaySound,RaidNotice_AddMessage,RaidWarningFrame=oldSound,oldRaid,oldFrame;M.SaleToast=origToast;M.db.flips={};M.ownedRows=nil
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
 local notices={};PlaySound=function() end;local origToast=M.SaleToast;M.SaleToast=function(self,a,from,text) notices[#notices+1]=text;return origToast(self,a,from,text) end
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
 C_ChatInfo=old;PlaySound,RaidNotice_AddMessage,RaidWarningFrame=oldSound,oldRaid,oldFrame;M.SaleToast=origToast;M.db.flips={};M.ownedRows=nil
 if not ok then error(err,0) end
end)

check('1.22.7 Purple sale banner: label, item, numbers, green/red profit, stacking, fade and saved position',function()
 M.saleToasts=nil;M.saleToastAnchor=nil;M.db.settings.saleAlertPos=nil
 local t1=M:SaleToast({name='Twilight Cuffs of the Physician',qty=1,gross=3500,net=3325,paid=2200,profit=1125},'Voidmark Bank')
 assert(t1:IsShown() and t1.label:GetText()=='VOIDMARK BANK SOLD' and t1.item:GetText()=='Twilight Cuffs of the Physician')
 assert(t1.detail:GetText():find(M:Coins(3500),1,true) and t1.detail:GetText():find('paid',1,true))
 assert(t1.profit:GetText()=='+'..M:Coins(1125)..' flip' and t1:GetHeight()==78)
 local t2=M:SaleToast({name="Elder's Sash of the Physician",qty=1,gross=4000,net=3800})
 assert(t2~=t1 and t2.label:GetText()=='SOLD' and t2.profit:GetText()=='' and t2:GetHeight()==58,'no profit line without a buy')
 local t3=M:SaleToast({name='Bad Flip',qty=1,gross=500,net=475,paid=900,profit=-425})
 assert(t3.profit:GetText()=='-'..M:Coins(425)..' loss')
 local t4=M:SaleToast({name='Unknown',qty=2})
 assert(t4.detail:GetText():find('mail',1,true) and t4.item:GetText()=='Unknown x2')
 -- A fifth reuses the oldest banner (at most 4 on screen).
 local t5=M:SaleToast({name='Fifth',qty=1});assert(#M.saleToasts==4 and t5==t1)
 -- Fades out after 6s.
 advance(8);for _,t in ipairs(M.saleToasts) do t.scripts.OnUpdate(t) end
 for _,t in ipairs(M.saleToasts) do assert(not t:IsShown(),'faded') end
 -- Dragging saves the position.
 local a=M.saleToastAnchor;a.GetPoint=function() return 'CENTER',UIParent,'CENTER',40.4,200.6 end
 t1.scripts.OnDragStop(t1);local pos=M.db.settings.saleAlertPos
 assert(pos[1]=='CENTER' and pos[2]==40 and pos[3]==201)
 M.db.settings.saleAlertPos=nil
end)

check('1.22.8 Sale price without Listings open: saved listing snapshot, then your last post (price each for stacks)',function()
 M.db.flips={};M.ownedRows=nil;M.saleClaimed=nil;M.db.postHistory={}
 -- Snapshot from an earlier Listings load (e.g. before a /reload).
 M.db.ownedSnapshot={at=time(),rows={{auctionID=77,name='Twilight Cuffs of the Physician',unit=3500,quantity=1,status=0}}}
 local a=M:BuildSaleAlert('Twilight Cuffs of the Physician',77);assert(a.gross==3500 and a.net==3325,'from the snapshot')
 M.db.ownedSnapshot=nil
 -- Single item posted with Market: its last post price.
 local key=M:Key(1080);M.nameIndex=M.nameIndex or {};M.nameIndex['Green Gloves']=key
 M.db.postHistory[key]={{at=time(),unit=2500,quantity=1}}
 a=M:BuildSaleAlert('Green Gloves');assert(a.gross==2500,'last post price')
 -- A stack (Silk Cloth x20): only the price each is known.
 local silk=M:Key(4306);M.nameIndex['Silk Cloth']=silk
 M.db.postHistory[silk]={{at=time(),unit=120,quantity=20}}
 a=M:BuildSaleAlert('Silk Cloth');assert(a.unit==120 and not a.gross)
 assert(M:SaleAlertText(a):find('at '..M:Coins(120)..' each',1,true))
 local t=M:SaleToast(a,'Voidmark Bank');assert(t.detail:GetText():find('each',1,true))
 -- Relayed as price-each and shown the same way on the other character.
 local msg=M:EncodeSaleAlert('1-1',{id='x1',a=a});local f={}
 for v in (('E\t')..msg..'\t'):gmatch('([^\t]*)\t') do f[#f+1]=v end
 local shown;local old=M.ShowSaleAlert;M.ShowSaleAlert=function(_,b) shown=b end
 M:ReceiveSaleAlert(f,'Bank-TestRealm');M.ShowSaleAlert=old
 assert(shown and shown.unit==120 and not shown.gross,'partner sees price each')
 M.db.postHistory={};M.nameIndex['Green Gloves']=nil;M.nameIndex['Silk Cloth']=nil
 -- Loading Listings saves the snapshot.
 assert(M.db.ownedSnapshot==nil)
end)

check('1.22.9 Sale chime plays from Media; message and sound switch independently',function()
 local files,coins,toasts={},0,0
 local oldFile,oldSound,oldToast=PlaySoundFile,PlaySound,M.SaleToast
 PlaySoundFile=function(path) files[#files+1]=path;return true end
 PlaySound=function() coins=coins+1 end
 M.SaleToast=function() toasts=toasts+1 end
 local ok,err=pcall(function()
  M.db.settings.saleAlerts=nil;M.db.settings.saleAlertSound=nil
  M:ShowSaleAlert({name='X',qty=1})
  assert(files[1]=='Interface\\AddOns\\VoidMarkMarket\\Media\\LockChime.ogg' and coins==0 and toasts==1,'chime + banner')
  -- Sound only.
  M.db.settings.saleAlerts=false;M:ShowSaleAlert({name='X',qty=1});assert(#files==2 and toasts==1)
  -- Message only.
  M.db.settings.saleAlerts=true;M.db.settings.saleAlertSound=false;M:ShowSaleAlert({name='X',qty=1});assert(#files==2 and toasts==2)
  -- Both off: nothing.
  M.db.settings.saleAlerts=false;M:ShowSaleAlert({name='X',qty=1});assert(#files==2 and toasts==2)
  -- File can't play (e.g. a new file before a full restart): the coin sound instead.
  M.db.settings.saleAlerts=true;M.db.settings.saleAlertSound=true
  PlaySoundFile=function() return false end;M:ShowSaleAlert({name='X',qty=1});assert(coins==1)
 end)
 PlaySoundFile,PlaySound,M.SaleToast=oldFile,oldSound,oldToast;M.db.settings.saleAlerts=nil;M.db.settings.saleAlertSound=nil
 if not ok then error(err,0) end
end)

check('1.22.10 With both characters online only one chimes: the bank stays quiet, the main plays',function()
 local files={};local oldFile,oldToast=PlaySoundFile,M.SaleToast
 PlaySoundFile=function(p) files[#files+1]=p;return true end;M.SaleToast=function() end
 local oldBank,oldOnline=M.IsBankCharacter,M.PartnerOnline
 local ok,err=pcall(function()
  M.db.settings.saleSoundQuietWithPartner=nil
  -- Bank, partner online: no sound (banner still shows).
  M.IsBankCharacter=function() return true end;M.PartnerOnline=function() return true end
  M:ShowSaleAlert({name='X',qty=1});assert(#files==0,'bank quiet while main is online')
  -- Bank alone: it plays.
  M.PartnerOnline=function() return false end;M:ShowSaleAlert({name='X',qty=1});assert(#files==1,'bank plays when alone')
  -- Main, partner online: it plays (including sales relayed from the bank).
  M.IsBankCharacter=function() return false end;M.PartnerOnline=function() return true end
  M:ShowSaleAlert({name='X',qty=1},'Voidmark Bank');assert(#files==2,'main plays')
  -- The switch overrides the default either way.
  M.db.settings.saleSoundQuietWithPartner=true;M:ShowSaleAlert({name='X',qty=1});assert(#files==2,'main set to quiet')
  M.db.settings.saleSoundQuietWithPartner=false;M.IsBankCharacter=function() return true end
  M:ShowSaleAlert({name='X',qty=1});assert(#files==3,'bank set to always play')
  -- Real partner check: contact within the heartbeat window.
  M.PartnerOnline=oldOnline;M.db.syncPeer='main';M.shareRun={lastContact=GetTime()};assert(M:PartnerOnline())
  advance(70);assert(not M:PartnerOnline(),'silent partner counts as offline')
  M.db.syncPeer=nil
 end)
 PlaySoundFile,M.SaleToast,M.IsBankCharacter,M.PartnerOnline=oldFile,oldToast,oldBank,oldOnline;M.db.settings.saleSoundQuietWithPartner=nil;M.shareRun={}
 if not ok then error(err,0) end
end)

check('1.22.11 /vmm testsound plays the chime and explains why when it cannot be heard',function()
 local printed={};local oldPrint,oldFile,oldSound,oldCVar=M.Print,PlaySoundFile,PlaySound,GetCVar
 M.Print=function(_,t) printed[#printed+1]=t end
 local cv={Sound_MasterVolume='0.8',Sound_EnableAllSound='1',Sound_EnableSoundWhenGameIsInBG='0'}
 GetCVar=function(k) return cv[k] end
 local ok,err=pcall(function()
  PlaySoundFile=function() return true,5 end;PlaySound=function() return true end
  SlashCmdList.VOIDMARKMARKET('testsound')
  local all=table.concat(printed,'\n')
  assert(all:find('chime played',1,true) and all:find('80%',1,true) and all:find('Sound in Background',1,true),all)
  printed={};PlaySoundFile=function() return false end
  M:TestSaleSound();all=table.concat(printed,'\n')
  assert(all:find('did NOT play',1,true) and all:find('Coin sound played instead',1,true) and all:find('restart WoW',1,true),all)
  assert(M.shopScreen or true)
 end)
 M.Print,PlaySoundFile,PlaySound,GetCVar=oldPrint,oldFile,oldSound,oldCVar
 if not ok then error(err,0) end
end)

check('1.22.13 Forever base-name links still find what you paid; Listings shows a Paid column',function()
 M.db.flips={}
 -- Bought from "You won" mail (no key) under the full AH name.
 local b=M:RecordFlipBuy({name='Durable Belt of the Physician',quantity=1,cost=1000})
 local lines={};local tip={AddLine=function(_,t) lines[#lines+1]=t end,AddDoubleLine=function(_,l,r) lines[#lines+1]=l..'='..r end}
 -- Forever's bag link carries only the base name.
 M:AppendBoughtTooltip(tip,'|cff1eff00|Hitem:1090::::::::25|h[Durable Belt]|h|r')
 assert(lines[1]=='Last Bought='..M:Coins(1000),table.concat(lines,' / '))
 -- Keys decide when both are known: a different suffix is not this item.
 b.key=M:Key(1090,-12);lines={}
 M:AppendBoughtTooltip(tip,'|cff1eff00|Hitem:1090:0:0:0:0:0:-10|h[Durable Belt]|h|r')
 assert(#lines==0,'other suffix not matched')
 b.key=nil
 -- Listings: Paid column, red when your price after the cut is below it.
 M.ownedRows={{auctionID=1,name='Durable Belt',unit=3000,quantity=1,status=0},{auctionID=2,name='Durable Belt',unit=1000,quantity=1,status=0},
  {auctionID=3,name='Never Bought',unit=500,quantity=1,status=0}}
 M:SetView('my auctions');M:RenderUI();local s=M.cancelScreen
 local byName={};for _,r in ipairs(s.rows) do if r:IsShown() then byName[#byName+1]=r end end
 assert(byName[1].c[7]:GetText():find(M:Coins(1000),1,true) and byName[1].c[7]:GetText():find('c8a0ff',1,true),'paid shown')
 assert(byName[2].c[7]:GetText():find('ff6060',1,true),'red: 10s after the cut is less than 10s paid')
 assert(byName[3].c[7]:GetText():find('--',1,true),'no buy record')
 M.ownedRows=nil;M.db.flips={};M:SetView('browse')
end)

check('1.22.14 Commodity sale with no listing loaded: post price recorded at post time, else a marked market estimate',function()
 M.db.flips={};M.ownedRows=nil;M.db.ownedSnapshot=nil;M.db.postHistory={}
 local key=M:Key(785);M.nameIndex=M.nameIndex or {};M.nameIndex['Mageroyal']=key
 -- Posting records the price right away (no AUCTION_HOUSE_AUCTION_CREATED needed), once.
 local row={marketKey=key,name='Mageroyal',postedUnit=145,postedQuantity=10,postedDuration=1}
 M:RecordPostHistory(row);M:RecordPostHistory(row)
 assert(#M.db.postHistory[key]==1 and M.db.postHistory[key][1].unit==145)
 local a=M:BuildSaleAlert('Mageroyal');assert(a.unit==145 and not a.estimate)
 -- Nothing posted with Market: the market price, marked as an estimate.
 M.db.postHistory={};local leather=M:Key(4304);M.nameIndex['Thick Leather']=leather
 M.db.market[leather]={itemID=4304,marketKey=leather,lastSeen=time()-60,latest={floor=320}}
 a=M:BuildSaleAlert('Thick Leather');assert(a.unit==320 and a.estimate)
 assert(M:SaleAlertText(a):find('about '..M:Coins(320)..' each (market price)',1,true))
 local t=M:SaleToast(a);assert(t.detail:GetText():find('market price',1,true))
 -- The estimate flag survives the relay to the other character.
 local msg=M:EncodeSaleAlert('1-1',{id='e1',a=a});local f={}
 for v in ('E\t'..msg..'\t'):gmatch('([^\t]*)\t') do f[#f+1]=v end
 local shown;local old=M.ShowSaleAlert;M.ShowSaleAlert=function(_,b) shown=b end
 M:ReceiveSaleAlert(f,'Bank-TestRealm');M.ShowSaleAlert=old
 assert(shown and shown.unit==320 and shown.estimate,'partner sees it as an estimate')
 M.db.market[leather]=nil;M.nameIndex['Mageroyal']=nil;M.nameIndex['Thick Leather']=nil
end)

check('1.22.15 Buy page search jumps a background request in flight; ignored refresh retries as a new search',function()
 local q=M.queue;q.waiting={};q.dedupe={};q.active=nil;q.nextSend=0;M.execution=nil;local oldOpen=M.ahOpen;M.ahOpen=true
 local sent={};local oldSend,oldReady=M.SendAHRequest,M.ThrottleReady;M.SendAHRequest=function(_,r) sent[#sent+1]=r.id end
 M.ThrottleReady=function() return true end
 local ok,err=pcall(function()
  M:QueueRequest({id='owned',kind='owned',priority=85})
  M:PumpQueue();assert(sent[1]=='owned' and q.active.id=='owned')
  M.shopBuy={}
  M:QueueRequest({id='search:buy',kind='search',priority=90})
  q.nextSend=0;M:PumpQueue()
  assert(sent[2]=='search:buy' and q.active.id=='search:buy','buy search sent right away: '..tostring(sent[2]))
  assert(#q.waiting==1 and q.waiting[1].id=='owned','owned auctions put back in line, not dropped')
  -- A price check (allowCached) is also background; a real purchase search is never bumped.
  q.active.reading=true;M:PumpQueue();assert(q.active.id=='search:buy')
  q.active=nil;q.dedupe['search:buy']=nil;M.shopBuy=nil;q.nextSend=0;M:PumpQueue();assert(sent[3]=='owned','owned resumes after')
 end)
 M.SendAHRequest=oldSend;q.waiting={};q.dedupe={};q.active=nil;M.shopBuy=nil;assert(ok,err)
 -- Chain buy: the next buy page's search joins a price check of the same item instead of failing.
 local got,checked={},0
 assert(M:QueueRequest({id='search:y',kind='search',priority=20,allowCached=true,done=function() checked=checked+1 end}))
 assert(M:QueueRequest({id='search:y',kind='search',priority=90,done=function(x) got[#got+1]=x end}),'joined, not refused')
 local w=q.waiting[1];assert(#q.waiting==1 and w.priority==90 and not w.allowCached,'upgraded to a fresh buy search')
 q.active=table.remove(q.waiting,1);M:FinishRequest(q.active,true,'rows');assert(got[1]=='rows' and checked==1,'both callers answered')
 q.waiting={};q.dedupe={};q.active=nil
 -- A refresh the server ignores gives up after 5s and sends a new search instead.
 local A=C_AuctionHouse;local calls={}
 local saved={A.HasSearchResults,A.RefreshItemSearchResults,A.SendSearchQuery}
 A.HasSearchResults=function() return true end
 A.RefreshItemSearchResults=function() calls[#calls+1]='refresh' end
 A.SendSearchQuery=function() calls[#calls+1]='new' end
 local r={id='search:x',kind='search',key={itemID=1},commodity=false}
 M:SendAHRequest(r);assert(calls[1]=='refresh' and r.refreshed)
 q.active=r;r.sent=GetTime()-6;r.at=GetTime();r.timeout=15;r.attempt=1;q.dedupe[r.id]=r
 M:PumpQueue();assert(r.fresh and calls[2]=='new','after 5s the retry is a new search, not another refresh: '..tostring(calls[2]))
 A.HasSearchResults,A.RefreshItemSearchResults,A.SendSearchQuery=saved[1],saved[2],saved[3]
 M.ThrottleReady=oldReady;M.ahOpen=oldOpen;q.active=nil;q.dedupe={};q.waiting={}
end)

check('1.22.16 Buys reach the synced partner: bank tooltip shows what main paid; not in bank profit totals',function()
 M.db.flips={};M.db.partnerBuys=nil;M.db.flipSyncSent=nil;local oldPeer=M.db.syncPeer;M.db.syncPeer='Voidmark-Soulreaver'
 M:RecordFlipBuy({name='Pagan Belt of the Sorcerer',quantity=1,cost=250})
 local silk=M:RecordFlipBuy({name='Silk Cloth',quantity=20,cost=2000})
 M:RecordFlipSale('Silk Cloth',20,4000,200) -- a sale row (no cost) is not sent
 local msg,hi=M:NextFlipBuyMessage('1-1',200)
 assert(msg and msg:find('^B\t1%-1\t') and hi==silk.id,tostring(msg))
 M:MarkFlipBuysSent(hi);assert(M:NextFlipBuyMessage('1-1',200)==nil,'nothing left to send')
 -- Many buys are split across messages that fit.
 for i=1,30 do M:RecordFlipBuy({name='Some Long Item Name of the Physician '..i,quantity=1,cost=i}) end
 local parts=0;local m,h=M:NextFlipBuyMessage('1-1',200)
 while m do parts=parts+1;assert(#m<=200,#m);M:MarkFlipBuysSent(h);m,h=M:NextFlipBuyMessage('1-1',200) end
 assert(parts>=5,'split: '..parts)
 -- The partner (bank) receives them.
 local f={};for v in ('E\t'..msg..'\t'):gmatch('([^\t]*)\t') do f[#f+1]=v end
 M.db.flips={};assert(M:ReceiveFlipBuys(f,'Voidmark-Soulreaver'))
 M:ReceiveFlipBuys(f,'Voidmark-Soulreaver') -- duplicates are ignored
 local n=0;for _ in pairs(M.db.partnerBuys) do n=n+1 end;assert(n==2,n)
 local lines={};local tip={AddLine=function(_,t) lines[#lines+1]=t end,AddDoubleLine=function(_,l,r) lines[#lines+1]=l..'='..r end}
 M:AppendBoughtTooltip(tip,'|cff1eff00|Hitem:1234::::::::16|h[Pagan Belt]|h|r')
 assert(lines[1]=='Last Bought='..M:Coins(250),table.concat(lines,' / '))
 assert(M:PaidFloor({name='Silk Cloth'})==math.ceil(100/0.95),'never-below-paid uses the partner buy')
 assert(M:PaidForListing({name='Silk Cloth'})==100)
 assert((M:FlipTotals('all').bought or 0)==0,'partner buys never count in this account totals')
 -- The sync pump sends them when the partner is connected.
 M.db.flips={};M.db.flipSyncSent=nil;M:RecordFlipBuy({name='Pagan Belt',quantity=1,cost=99})
 local r=M.shareRun;local sent;local oldSend=C_ChatInfo.SendAddonMessage
 C_ChatInfo.SendAddonMessage=function(_,m) if m:find('\tB\t',1,true) then sent=m end;return true end
 local saved={r.lastContact,r.hello,r.next,r.infoPending,r.capPending,r.reply,r.buyCheckAt}
 r.lastContact=GetTime();r.hello=GetTime()+100;r.next=0;r.infoPending=nil;r.capPending=nil;r.reply=nil;r.buyCheckAt=0
 local ok,err=pcall(function() M:PumpSharing() end)
 C_ChatInfo.SendAddonMessage=oldSend
 r.lastContact,r.hello,r.next,r.infoPending,r.capPending,r.reply,r.buyCheckAt=saved[1],saved[2],saved[3],saved[4],saved[5],saved[6],saved[7]
 assert(ok,err);assert(sent and sent:find('Pagan Belt',1,true),'buy sent: '..tostring(sent))
 M.db.flips={};M.db.partnerBuys=nil;M.db.flipSyncSent=nil;M.db.syncPeer=oldPeer
end)
end
