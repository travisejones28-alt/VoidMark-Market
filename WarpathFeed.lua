local _,M=...
-- 1.24.0 Warpath feed: the whole latest scan between your accounts, by file.
--
-- The in-game bank sync is held to about 1 KB/s by the game, so a full scan
-- takes many minutes to cross (the "receiving 98%" wait). Both accounts run
-- on one PC, so Warpath can carry it as a file instead:
--  1. On logout or /reload, Market writes this character's sync journal
--     (every latest price and list change) to VoidMarkMarketFeedOut.
--  2. Warpath sees the saved file change and copies the journal into the
--     small VoidMarkMarket_Feed addon, which every account loads.
--  3. At login or /reload the partner's copy is applied with the same checks
--     as sync pages, and the sync jumps ahead to that point. The live sync
--     keeps running for anything newer.
local FEED_VERSION=1
local function finite(v,lo,hi) return M:Finite(v,lo,hi) and v%1==0 end
local function squash(s) return tostring(s or ''):gsub('%s',''):lower() end
local function prettyName(key)
 return (tostring(key or ''):gsub("(%a)([%w']*)",function(a,b) return a:upper()..b end))
end

-- Finish publishing the last scan to the journal now (normally a slow
-- background job), so a reload right after a scan still carries all of it.
function M:FlushScanSharing()
 local job=self.jobs and self.jobs['share-scan']
 if not job then return end
 self.feedFlushing=true
 for _=1,1000 do
  local ok,finished=pcall(job.step,math.huge)
  if not ok or finished then break end
 end
 self.jobs['share-scan']=nil
 if job.done then pcall(job.done) end
 self.feedFlushing=nil
end

function M:BuildFeedOut()
 if self.persistenceBlocked or not self.db then return end
 self:FlushScanSharing()
 local j=self.db.shareJournal
 if type(j)~='table' or type(j.rows)~='table' or not finite(j.seq,1,1e12) or type(j.epoch)~='string' then
  VoidMarkMarketFeedOut=nil;return
 end
 local keys={}
 for k,v in pairs(j.rows) do if type(k)=='number' and type(v)=='string' then keys[#keys+1]=k end end
 table.sort(keys)
 local rows={};for i,k in ipairs(keys) do rows[i]=j.rows[k] end
 local scan=self.db.latestScan
 local who=self.SharingUnitCharacter and self.SharingUnitCharacter('player')
 VoidMarkMarketFeedOut={version=FEED_VERSION,economy=self.economyID,character=who or '',epoch=j.epoch,seq=j.seq,
  savedAt=time(),scanAt=type(scan)=='table' and tonumber(scan.completedAt) or 0,
  auctions=type(scan)=='table' and tonumber(scan.auctionsProcessed) or 0,rows=rows}
end
M:RegisterHandler('PLAYER_LOGOUT',function(self) self:BuildFeedOut() end)

-- The newest copy Warpath made from the paired partner on this realm/faction.
function M:PickWarpathFeed()
 local feeds=VoidMarkMarket_WarpathFeeds
 if type(feeds)~='table' or not self.db or not self.db.syncPeer then return end
 local peer=self.SharingNameKey(self.db.syncPeer);local pick
 for _,f in ipairs(feeds) do
  if type(f)=='table' and (tonumber(f.version) or 0)==FEED_VERSION and squash(f.economy)==squash(self.economyID)
   and self.SharingNameKey(f.character)==peer and type(f.rows)=='table' and type(f.epoch)=='string'
   and finite(f.seq,1,1e12) and finite(f.savedAt,1,time()+86400) then
   if not pick or f.savedAt>pick.savedAt then pick=f end
  end
 end
 return pick
end

function M:ImportWarpathFeed()
 if self.persistenceBlocked or not self.db or not self.db.syncPeer then return end
 local pick=self:PickWarpathFeed();if not pick then return end
 local peer=self.db.syncPeer
 local rx=self.db.shareReceived[peer]
 local last=self.db.warpathFeed
 if rx and rx.epoch==pick.epoch and (rx.seq or 0)>=pick.seq then return end -- the sync already got this far
 if type(last)=='table' and last.epoch==pick.epoch and last.seq==pick.seq and last.savedAt==pick.savedAt then return end
 local rows,i,applied,skipped=pick.rows,0,0,0
 self.feedImporting=true
 self:AddJob('warpath-feed',function(start)
  while true do
   i=i+1;local line=rows[i]
   if line==nil then return true end
   local p=type(line)=='string' and self.SharingDecode(self,line)
   if p and self.SharingApply(self,p) then applied=applied+1 else skipped=skipped+1 end
   if debugprofilestop()-start>=self.budget then return false end
  end
 end,function()
  self.feedImporting=nil
  rx=self.db.shareReceived[peer]
  if type(rx)~='table' or rx.epoch~=pick.epoch then rx={epoch=pick.epoch,seq=0};self.db.shareReceived[peer]=rx end
  if pick.seq>(rx.seq or 0) then rx.seq=pick.seq end
  if not rx.total or rx.total<rx.seq then rx.total=rx.seq end
  local scanAt=tonumber(pick.scanAt) or 0
  if scanAt>0 and scanAt>(rx.scanAt or 0) then rx.scanAt=scanAt;rx.scanAuctions=tonumber(pick.auctions) or nil end
  if rx.seq>=rx.total then
   self.db.syncLastReceivedCompleteAt=math.max(tonumber(self.db.syncLastReceivedCompleteAt) or 0,math.min(time(),pick.savedAt))
  end
  self.db.warpathFeed={epoch=pick.epoch,seq=pick.seq,savedAt=pick.savedAt,scanAt=scanAt,applied=applied,skipped=skipped,at=time()}
  -- Tell the partner where we are now, so it skips everything the file carried.
  local r=self.shareRun
  if r then
   if r.buf then for k in pairs(r.buf) do if k<rx.seq then r.buf[k]=nil end end end
   if r.lastContact then r.reply=table.concat({'Q',rx.epoch,rx.seq},'\t');r.next=0 end
  end
  if self.WarmItemNames then self:WarmItemNames() end
  if self.view=='browse' then self.browseNamesDirty=self.browseNamesDirty or GetTime()+1 end
  self.browseRows=nil
  local age=scanAt>0 and (' (scan from '..self:PriceAge(scanAt)..')') or ''
  self:Print('Warpath: loaded '..applied..' prices and list changes from '..prettyName(self.SharingNameKey(peer))..age..'.')
  self:RefreshUI()
 end)
end
M:RegisterHandler('PLAYER_LOGIN',function(self) self:ImportWarpathFeed() end)

-- Partner's newest scan time (from the feed or the sync), for the status line.
function M:PartnerScan()
 local peer=self.db and self.db.syncPeer;if not peer then return end
 local rx=self.db.shareReceived[peer]
 if type(rx)~='table' or not finite(rx.scanAt,1,time()+60) then return end
 return rx.scanAt,rx.scanAuctions,prettyName(self.SharingNameKey(peer))
end

-- After the first scan of the day on this character, offer the reload that
-- writes it to disk for Warpath. Later scans don't ask (the sync covers them).
StaticPopupDialogs=StaticPopupDialogs or {}
function M:OfferFeedSave()
 if self.feedFlushing or self.persistenceBlocked or not self.db or not self.db.syncPeer then return end
 if self.db.settings.warpathSavePrompt==false then return end
 local day=date('%Y-%m-%d')
 if self.db.feedPromptDay==day then return end
 if InCombatLockdown and InCombatLockdown() then self.feedPromptPending=true;return end
 self.db.feedPromptDay=day;self.feedPromptPending=nil
 if not StaticPopup_Show then return end
 StaticPopupDialogs.VOIDMARKMARKET_FEEDSAVE=StaticPopupDialogs.VOIDMARKMARKET_FEEDSAVE or {
  text='VoidMark Market: first scan of the day is done.\n\nReload now so Warpath can hand it to your other characters?',
  button1='Reload now',button2='Later',
  OnAccept=function() ReloadUI() end,
  timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
 StaticPopup_Show('VOIDMARKMARKET_FEEDSAVE')
end
M:RegisterHandler('PLAYER_REGEN_ENABLED',function(self) if self.feedPromptPending then self:OfferFeedSave() end end)
local queue=M.QueueScanSharing
function M:QueueScanSharing(at)
 queue(self,at)
 local job=self.jobs and self.jobs['share-scan']
 if job and not job.feedHooked then
  local done=job.done;job.feedHooked=true
  job.done=function(...) if done then done(...) end;M:OfferFeedSave() end
 end
end
