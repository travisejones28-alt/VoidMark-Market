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

check('1.21 fast mode: only after the partner says so; pages spread over lanes and carry more rows',function()
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
  assert(#sent>8,'more pages in flight than the old window: '..#sent)
  -- A throttled lane backs off; the others carry on.
  sent={};local throttled='VMMkt2b'
  C_ChatInfo.SendAddonMessage=function(prefix,msg) if prefix==throttled then return 3 end;sent[#sent+1]={prefix,msg};return 0 end
  M:ReceiveSharing('VMMkt2',M.economyID..'\tQ\t'..j.epoch..'\t'..r.sentHi,'WHISPER','Bank-TestRealm')
  advance(3);r.next=0;M:PumpSharing()
  for _,m in ipairs(sent) do assert(m[1]~=throttled) end
  assert(#sent>0,'other lanes still sending')
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
end
