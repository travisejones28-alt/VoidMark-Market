-- 1.23.0 mispost sniper (Snipe.lua)
return function(M,check,jobs,advance,emit)
 local A=C_AuctionHouse
 local saved={A.IsThrottledMessageSystemReady,A.GetBrowseResults,A.HasFullBrowseResults,A.RequestMoreBrowseResults,A.SendBrowseQuery,A.GetItemKeyInfo}
 local oldLows,oldBase=M.db.dailyLows,M.db.dailyLowsBase
 local pages,page={},1
 local sent={}
 A.IsThrottledMessageSystemReady=function() return true end
 A.SendBrowseQuery=function(q) sent[#sent+1]='browse';page=1 end
 A.RequestMoreBrowseResults=function() sent[#sent+1]='more';page=page+1 end
 A.HasFullBrowseResults=function() return page>=#pages end
 A.GetBrowseResults=function()
  local out={};for p=1,page do for _,r in ipairs(pages[p] or {}) do out[#out+1]=r end end;return out
 end
 A.GetItemKeyInfo=function(k) return {itemName='Item '..k.itemID,isCommodity=false} end
 local function row(id,price,suffix) return {itemKey={itemID=id,itemSuffix=suffix or 0,itemLevel=0,battlePetSpeciesID=0},minPrice=price,totalQuantity=1} end
 local day=math.floor(time()/86400)
 local function history(id,price,days)
  local key=M:Key(id,0,0,0);M.db.dailyLows=M.db.dailyLows or {}
  local t={};for d=1,days or 4 do t[day-d]=price end;M.db.dailyLows[tostring(key)]=t;return key
 end
 local function reset()
  M:StopSnipe();M.snipe=nil;M.snipeView=false;M.shopBuy=nil
  M:CancelRequests('snipe test');M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil;M.queue.nextSend=0
  M.ahOpen=true;M.execution={state='idle',message='idle'};M.db.settings.snipePercent=nil;M.db.settings.snipeMinGain=nil
  sent={};page=1
 end
 -- Runs the sniper until the current round is finished.
 local function round()
  local before=M.snipe and M.snipe.rounds or 0
  for _=1,60 do
   advance(1);M:SnipeTick();M:PumpQueue()
   local r=M.queue.active
   if r and r.kind=='browse' and r.id=='snipe' then emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
   elseif r and r.kind=='browsemore' then emit('AUCTION_HOUSE_BROWSE_RESULTS_ADDED') end
   jobs()
   if M.snipe and not M.snipe.round and M.snipe.rounds>before and not M.queue.active then return end
  end
  error('sniper round never finished')
 end
 check('1.23.0 Sniper flags a mispost under 50% of its own average with a real gain',function()
  reset()
  history(91001,10000);history(91002,10000);history(91003,3000)
  pages={{row(91001,2000),row(91002,6000),row(91003,500),row(91004,10)}}
  assert(M:StartSnipe());round()
  local hits=M:SnipeRows()
  assert(#hits==1 and hits[1].marketKey==M:Key(91001,0,0,0),'one hit expected, got '..#hits)
  assert(hits[1].pct==20 and hits[1].gain==9500-2000 and hits[1].status=='MISPOST')
  -- 60% is not a mispost; a 17% item with only 23s gain is under the 50s minimum; no history = never.
 end)
 check('1.23.0 Sniper never trusts the all-suffixes estimate',function()
  reset();M.db.dailyLowsBase=M.db.dailyLowsBase or {}
  local t={};for d=1,4 do t[day-d]=20000 end;M.db.dailyLowsBase[91010]=t
  pages={{row(91010,1000,-7)}}
  M:StartSnipe();round();assert(#M:SnipeRows()==0)
 end)
 check('1.23.0 Sniper reads every page and saves nothing to prices or history',function()
  reset();history(91001,10000)
  local lows=M.db.dailyLows[tostring(M:Key(91001,0,0,0))];local copy={};for k,v in pairs(lows) do copy[k]=v end
  local seenBefore=0;for _ in pairs(M.db.liveSeen or {}) do seenBefore=seenBefore+1 end
  local journal=M.db.shareJournal.seq
  pages={{row(91020,5)},{row(91021,5)},{row(91001,1500)}}
  M:StartSnipe();round()
  assert(M.snipe.lastRound.pages==3 and M.snipe.lastRound.items==3,'pages '..tostring(M.snipe.lastRound.pages))
  assert(#M:SnipeRows()==1,'hit on the last page')
  for k,v in pairs(copy) do assert(lows[k]==v) end
  local n=0;for k in pairs(lows) do n=n+1 end;local c=0;for _ in pairs(copy) do c=c+1 end;assert(n==c,'no daily low written')
  local seenAfter=0;for _ in pairs(M.db.liveSeen or {}) do seenAfter=seenAfter+1 end
  assert(seenAfter==seenBefore and M.db.shareJournal.seq==journal,'no live price or sync row')
 end)
 check('1.23.0 Sniper alerts once per mispost, marks it gone when bought, alerts again on a new one',function()
  reset();history(91001,10000)
  pages={{row(91001,2000)}}
  M:StartSnipe();round();assert(#M.snipe.hits==1)
  local first=M.snipe.hits[1];round();assert(M.snipe.hits[1]==first and #M.snipe.hits==1,'no repeat alert')
  pages={{row(91001,9000)}};round()
  assert(first.gone and first.status=='GONE' and M:SnipeHitCount()==0)
  pages={{row(91001,1000)}};round()
  assert(M:SnipeHitCount()==1 and M.snipe.hits[1].floor==1000)
 end)
 check('1.23.0 Sniper restarts a round when another browse replaces the AH list',function()
  reset();history(91001,10000)
  pages={{row(91030,5)},{row(91001,1000)}}
  M:StartSnipe();advance(1);M:SnipeTick();M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');jobs()
  M.browseOwner='browse-term:other'
  advance(1);M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_ADDED');jobs()
  assert(M.snipe.round==nil and M.snipe.lastError and M.snipe.lastError:find('restarting'))
  advance(10);round();assert(M:SnipeHitCount()==1)
 end)
 check('1.23.0 Sniper waits while you buy and stops when the AH closes',function()
  reset();history(91001,10000);pages={{row(91001,1000)}}
  M.shopBuy={};M:StartSnipe();advance(5);M:SnipeTick();assert(M.snipe.round==nil,"waits while buying");M.shopBuy=nil
  emit('AUCTION_HOUSE_CLOSED');M.ahOpen=false
  assert(not M.snipe.on);M:SnipeTick();assert(M.snipe.round==nil)
  assert(not M:StartSnipe(),'needs the AH open')
 end)
 check('1.23.0 Snipe Hits list in Shopping opens the normal buy page and any search leaves it',function()
  reset();history(91001,10000);pages={{row(91001,2000)}}
  M:StartSnipe();round();M:ShowSnipeHits()
  local rows=M:ShopVisibleRows();assert(#rows==1 and rows[1].status=='MISPOST')
  assert(M.view=='browse');M:RenderUI();local sc=M.shopScreen
  assert(sc.snipeButton:GetText()=='Stop Snipe' and sc.snipeHits:GetText():find('Hits %(1%)') and sc.status:GetText():find('Sniper ON'))
  assert(M:ListSearchStatus():find('Sniper ON'))
  M:ShopRowClicked(rows[1],'LeftButton');assert(M.shopBuy and M.shopBuy.key==rows[1].marketKey)
  M:ShopBuyClose();M:ShopSearch('Linen');assert(not M.snipeView)
 end)
 check('1.23.0 /vmm snipe pct and min change the thresholds',function()
  reset();history(91001,10000);pages={{row(91001,4500)}}
  M:SnipeCommand('pct 40');M:SnipeCommand('min 1g');assert(M:SnipePercent()==40 and M:SnipeMinGain()==10000)
  M:StartSnipe();round();assert(#M:SnipeRows()==0,'45% is above 40%')
  M:SnipeCommand('pct 95');assert(M:SnipePercent()==40,'out of range ignored')
  reset()
 end)
 A.IsThrottledMessageSystemReady,A.GetBrowseResults,A.HasFullBrowseResults,A.RequestMoreBrowseResults,A.SendBrowseQuery,A.GetItemKeyInfo=unpack(saved)
 M.db.dailyLows,M.db.dailyLowsBase=oldLows,oldBase
end
