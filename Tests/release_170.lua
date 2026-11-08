return function(M,check,jobs,advance)
local addon=VMM_ADDON_PATH or './'
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
end
local function tipLines()
 local lines={}
 return lines,{AddLine=function(_,s)lines[#lines+1]=s end,AddDoubleLine=function(_,a,b)lines[#lines+1]=a..':'..b end}
end
local function withChat(fn)
 local old=C_ChatInfo;local sent={};local result=0
 C_ChatInfo={RegisterAddonMessagePrefix=function()return 0 end,SendAddonMessage=function(_,msg,ch,target)
  sent[#sent+1]={msg=msg,ch=ch,target=target};return result end}
 local ok,err=pcall(fn,sent,function(v)result=v end)
 C_ChatInfo=old;if not ok then error(err,0) end
end

check('1.8 tooltip shows Vendor and Auction lines, a stack total, greys old prices and a no-data line',function()
 reset();local oldItem=C_Item;C_Item=nil
 local link='|Hitem:9001:0:0:0:0:0:0:0|h[Ore]|h'
 local oldInfo=GetItemInfo
 GetItemInfo=function()return 'Ore',nil,1,1,1,'Trade','Metal',20,'',999,0 end -- no vendor price
 local lines,tip=tipLines();M:AppendMarketTooltip(tip,link)
 assert(#lines==1 and lines[1]:find('Auction',1,true) and lines[1]:find('No price yet',1,true))
 GetItemInfo=function()return 'Bound',nil,1,1,1,'Armor','Cloth',1,'',999,0,0,0,1 end
 lines,tip=tipLines();M:AppendMarketTooltip(tip,link);assert(#lines==0) -- bind-on-pickup never reaches the AH
 GetItemInfo=function()return 'Ore',nil,1,1,1,'Trade','Metal',20,'',999,5 end
 M.db.settings.tooltipNoData=false;M.db.settings.tooltipVendor=true;lines,tip=tipLines();M:AppendMarketTooltip(tip,link);assert(#lines==1 and lines[1]=='Vendor:0g 0s 5c');M.db.settings.tooltipVendor=nil
 M.db.settings.tooltipNoData=nil;M.db.settings.tooltipVendor=true
 M.db.market[9001]={itemID=9001,marketKey=9001,name='Ore',lastSeen=time()-120,observations=8,confidenceScore=80,
  volatility=.1,fairValue=260,historySpan=10*86400,latest={floor=250,quantity=40},history={}}
 lines,tip=tipLines();M:AppendMarketTooltip(tip,link,20);local text=table.concat(lines,'\n')
 assert(text:find('Vendor x20:0g 1s 0c',1,true) and text:find('Auction:0g 2s 50c',1,true) and text:find('Auction x20:0g 50s 0c',1,true))
 assert(#lines==3 and not text:find('old)',1,true))
 M.db.settings.tooltipVendor=nil;lines,tip=tipLines();M:AppendMarketTooltip(tip,link);assert(#lines==1) -- off by default: Forever shows Sell Price itself
 advance(M.db.settings.maxDataAge+10)
 lines,tip=tipLines();M:AppendMarketTooltip(tip,link,1);text=table.concat(lines,'\n')
 assert(text:find('Auction |cff999999(',1,true) and text:find('old)',1,true) and not text:find('Auction x',1,true))
 GetItemInfo=oldInfo;C_Item=oldItem;reset()
end)

check('1.7 sync catch-up offers older trusted prices and re-seeds existing journals once',function()
 reset();local d=M.db
 local old=time()-3*3600 -- older than the freshness window, scanned before pairing
 d.market[9100]={itemID=9100,marketKey=9100,name='Old',lastSeen=old,latest={floor=777},confidenceScore=50}
 d.market[9101]={itemID=9101,marketKey=9101,name='Untrusted',lastSeen=old,latest={floor=5},cacheUntrusted=true}
 d.market[9102]={itemID=9102,marketKey=9102,name='Ancient',lastSeen=time()-400*86400,latest={floor=9}}
 d.lastDepthSnapshotAt=old
 local j=d.shareJournal;j.seeded=true -- pre-1.7 journal that skipped stale rows
 withChat(function() M:PairPeer('Bank');jobs() end)
 assert(j.seeded and j.catchUpSeed==2)
 local line=j.latest.P9100 and j.rows[j.latest.P9100]
 assert(line and line:find('P,9100,'..old..',777,0,',1,true))
 assert(not j.latest.P9101 and not j.latest.P9102)
 -- A receiver keeps its newer local observation and labels the old one by age.
 reset();M:PairPeer('Bank');local epoch='5-55';local peer='Bank-TestRealm'
 M.db.market[9100]={itemID=9100,marketKey=9100,lastSeen=time(),latest={floor=700}}
 M:ReceiveSharing('VMMkt2','TestRealm|Horde\tH\t'..epoch,'WHISPER',peer)
 M:ReceiveSharing('VMMkt2','TestRealm|Horde\tD\t'..epoch..'\t0\t1\t'..line,'WHISPER',peer)
 assert(M.db.sharedPrices[9100].floor==777 and M:PriceObservation(9100).floor==700)
 M.db.market[9100]=nil;local p=M:PriceObservation(9100)
 assert(p.floor==777 and p.source=='Synced account' and time()-p.at>M.db.settings.maxDataAge)
 -- Duplicate and out-of-order pages are acknowledged without applying twice.
 M:ReceiveSharing('VMMkt2','TestRealm|Horde\tD\t'..epoch..'\t0\t1\t'..line,'WHISPER',peer)
 M:ReceiveSharing('VMMkt2','TestRealm|Horde\tD\t'..epoch..'\t3\t4\t'..line,'WHISPER',peer)
 assert(M.db.shareReceived[M.db.syncPeer].seq==1 and M.shareRun.reply:find('Q\t'..epoch..'\t1',1,true))
 reset()
end)

check('1.7 sync skips a revision too large for one message instead of stalling, and retries throttled pages',function()
 withChat(function(sent,setResult)
  reset();M:PairPeer('Bank');jobs()
  local j=M.db.shareJournal;local r=M.shareRun
  j.seq=0;j.rows={};j.latest={}
  j.rows[1]='W,'..string.rep('x',220)..',9200,'..time()..',0,a';j.rows[2]='P,9201,'..time()..',55,0,0';j.seq=2
  M.shareRegistered=true;r.lastContact=GetTime();r.hello=GetTime()+100;r.cursor=0;r.next=0
  M:PumpSharing()
  assert(#sent==1 and sent[1].ch=='WHISPER')
  local f={};for v in (sent[1].msg..'\t'):gmatch('([^\t]*)\t') do f[#f+1]=v end
  assert(f[2]=='D' and f[4]=='0' and f[5]=='2' and f[6]=='P,9201,'..time()..',55,0,0' and r.oversized==1)
  -- A throttled send is retried shortly, not after the 4-second ack timeout.
  r.retry=0;r.next=0;r.cursor=0;setResult(3)
  M:PumpSharing();assert(#sent==2 and r.retry<=GetTime()+1.5)
  advance(2);r.next=0;setResult(0);M:PumpSharing();assert(#sent==3)
  reset()
 end)
end)

check('1.7 navigation exposes Shopping, Selling, Scanning, History and Settings; Safe Mode is gone',function()
 reset()
 for _,view in ipairs({'browse','selling','my auctions','market','banker','settings','vendor','crafting','tools'}) do
  assert(M.navigation[view],'missing nav '..view)
 end
 assert(M.navigation.market.text=='SCANNING' and M.navigation.banker.text=='HISTORY' and M.navigation.settings.text=='SETTINGS')
 M:SetView('market');M:RenderUI();assert(M.scanButton:IsShown() and M.historyAction:IsShown())
 M:SetView('banker');M:RenderUI();assert(M.historyAction:IsShown())
 M:SetView('settings');M:RenderUI();assert(M.settingsFrame:IsShown())
 -- No active Safe Mode code or text remains; the database only retires the old key.
 for line in io.lines(addon..'VoidMarkMarket.toc') do
  if line:match('%.lua$') then
   local n=0
   for l in io.lines(addon..line) do
    local low=l:lower()
    if low:find('safe ?mode') or low:find('safemode') then
     n=n+1;assert(line=='Database.lua' and l:find('root.settings.safeMode=nil',1,true),line..': '..l)
    end
   end
   if line=='Database.lua' then assert(n==1) end
  end
 end
 local toc=io.open(addon..'VoidMarkMarket.toc'):read('*a')
 assert(toc:find('## Version: '..M.version,1,true) and toc:find('## Interface: 16001',1,true) and M.version>='1.7.0')
 reset()
end)
end
