local _,M=...
-- Mispost sniper (1.23.0).
-- Re-reads the whole Auction House over and over with an empty browse search
-- (one lowest price per item, not the 15-minute full scan) and flags any item
-- listed far under its own 30-day price: a fat-fingered or misposted listing.
--  * Reference = the LOWER of this exact suffix's 30-day average (never the
--    all-suffixes estimate) and its newest full scan, which must be under 6
--    hours old (yours or Bank's). No recent scan = never fires.
--  * A hit needs both: price <= snipe % of average AND a resale gain (after the
--    5% AH cut) of at least the minimum gain. Defaults 50% and 50s.
--  * New hits chime, print in chat and list under Shopping > Snipe Hits.
--    Click a hit = the normal buy page (live listings, Buy Now, ledger, risk caps).
--    Buying always needs your click; nothing is bought automatically.
--  * Saves nothing to prices or history: a mispost must never become the
--    market price or tomorrow's reference.
-- /vmm snipe [on|off], /vmm snipe pct 40, /vmm snipe min 1g
local MAX_PAGES,MAX_HITS,ROUND_GAP=500,40,2
M.SNIPE_DEFAULT_PCT,M.SNIPE_DEFAULT_MIN=50,5000

function M:SnipePercent()
 local p=tonumber(self.db.settings.snipePercent)
 return (p and p>=5 and p<=90) and math.floor(p) or self.SNIPE_DEFAULT_PCT
end
function M:SnipeMinGain()
 local v=tonumber(self.db.settings.snipeMinGain)
 return (v and v>=1 and v<=1e10) and math.floor(v) or self.SNIPE_DEFAULT_MIN
end
local function state(self)
 self.snipe=self.snipe or {on=false,hits={},alerted={},rounds=0,nextRound=0}
 return self.snipe
end

M.SNIPE_SCAN_AGE=6*3600
-- What the item sells for now: the newest full-scan price (this account's
-- bait-resistant floor, or the synced Bank price), if it is recent.
function M:SnipeCurrentPrice(key)
 local best,at
 local m=self.db.market[key]
 if type(m)=='table' and type(m.latest)=='table' and not m.cacheUntrusted and not m.analysisIncomplete then
  local v=tonumber(m.latest.meaningfulFloor) or tonumber(m.latest.floor)
  if self:Finite(v,1,1e12) and self:Finite(m.lastSeen,time()-self.SNIPE_SCAN_AGE,time()+60) then best,at=v,m.lastSeen end
 end
 local p=self.db.sharedPrices and self.db.sharedPrices[key]
 if type(p)=='table' and self:Finite(p.floor,1,1e12) and self:Finite(p.at,time()-self.SNIPE_SCAN_AGE,time()+60) and (not at or p.at>at) then best=p.floor end
 return best
end
-- Is this lowest price a mispost? Returns the hit row or nil.
function M:SnipeCheck(key,itemID,floor,quantity,name)
 if key==nil or not self:Finite(floor,1,1e12) then return nil end
 local month,samples,approx=self:DealReference(key)
 if not month or approx then return nil end
 -- Prices move fast (a new server's prices fall for weeks), so a 30-day
 -- average alone calls half the AH a mispost. Also require a full scan from
 -- the last few hours (this account's or Bank's) and use the lower of the two:
 -- a mispost is far under what the item sells for now, not last week.
 local now=self:SnipeCurrentPrice(key)
 if not now then return nil end
 local ref=math.min(month,now)
 if ref<=floor then return nil end
 local pct=floor/ref*100
 if pct>self:SnipePercent() then return nil end
 local gain=math.floor(ref*(1-(self.db.settings.ahCut or 0.05)))-floor
 if gain<self:SnipeMinGain() then return nil end
 local m=self.db.market[key]
 return {marketKey=key,itemID=itemID,name=name or (m and m.name) or self:ItemName(itemID) or ('Item '..tostring(itemID)),
  floor=floor,quantity=tonumber(quantity),fair=ref,ref=ref,samples=samples,pct=math.floor(pct+0.5),gain=gain,
  confidence=m and m.confidence or 'Unknown',status='MISPOST',at=time()}
end

function M:SnipeAlert(hit)
 local s=state(self)
 s.alerted[hit.marketKey]=hit.floor
 for i=#s.hits,1,-1 do if s.hits[i].marketKey==hit.marketKey then table.remove(s.hits,i) end end
 table.insert(s.hits,1,hit);while #s.hits>MAX_HITS do table.remove(s.hits) end
 if self.db.settings.snipeSound~=false and self.PlaySaleSound and GetTime()>=(s.chimeAt or 0) then s.chimeAt=GetTime()+15;pcall(self.PlaySaleSound,self) end
 local text=('|cff40ff40MISPOST|r %s at %s - normally %s (%d%%), about +%s. Shopping > Snipe Hits to buy.')
  :format(hit.name,self:Coins(hit.floor),self:Coins(hit.ref),hit.pct,self:Coins(hit.gain))
 self:Print(text)
 if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage,UIErrorsFrame,'Mispost: '..hit.name..' '..hit.pct..'%',0.25,1,0.25) end
 self:RefreshUI()
end

function M:SnipeCanRun()
 return self.ahOpen and self:CanUseAuctionHouse() and C_AuctionHouse.SendBrowseQuery~=nil and C_AuctionHouse.GetBrowseResults~=nil
end
function M:StartSnipe()
 local s=state(self)
 if not self:SnipeCanRun() then self:Print('Open the Auction House to snipe');return false end
 s.on=true;s.nextRound=0;s.stopped=nil
 self:Print(('Sniper on: whole AH, flags %d%% of average or less and +%s or more. Keep the AH open.'):format(self:SnipePercent(),self:Coins(self:SnipeMinGain())))
 self:SnipeTick();self:RefreshUI();return true
end
function M:StopSnipe(reason)
 local s=state(self);if not s.on and not s.round then return end
 s.on=false;s.round=nil;self:CancelJob('snipe')
 local q=self.queue
 if q then for i=#q.waiting,1,-1 do local r=q.waiting[i];if r.id=='snipe' or r.id=='snipe:more' then table.remove(q.waiting,i);q.dedupe[r.id]=nil end end end
 if reason then self:Print('Sniper stopped: '..reason) end
 self:RefreshUI()
end
function M:ToggleSnipe() if state(self).on then self:StopSnipe() else self:StartSnipe() end end

-- One round = one empty browse, paged until the AH says it's complete.
function M:SnipeTick()
 local s=self.snipe;if not (s and s.on) or s.round then return end
 if not self:SnipeCanRun() then return end
 if GetTime()<(s.nextRound or 0) then return end
 -- Stand aside while you buy or a full scan is being processed.
 if self.shopBuy or (self.scanState and self.scanState.running) then return end
 local round={pages=0,read=0,items=0,seen={},pending={},started=GetTime()};s.round=round
 local function fail(why)
  if s.round~=round then return end
  s.round=nil;s.nextRound=GetTime()+ROUND_GAP*3;s.lastError=tostring(why or 'failed')
 end
 local done
 -- Reads queued pages in a frame-budgeted job. The next page is asked for at
 -- once (before reading), so no other browse can replace the AH's result list
 -- between our pages; if one does anyway, the round restarts.
 local function read()
  if self.jobs.snipe then return end
  self:AddJob('snipe',function(start)
   if s.round~=round then return true end
   local p=round.pending[1]
   while p do
    while p.from<=p.to do
     local b=p.results[p.from];p.from=p.from+1
     local k=b and b.itemKey
     if k and tonumber(b.minPrice) then
      local key=self:Key(k.itemID,k.itemSuffix,k.itemLevel,k.battlePetSpeciesID)
      round.items=round.items+1
      if round.seen[key]==nil or b.minPrice<round.seen[key] then round.seen[key]=b.minPrice end
      local old=s.alerted[key]
      if not old or b.minPrice<old then
       local info=C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(k)
       local hit=self:SnipeCheck(key,k.itemID,b.minPrice,b.totalQuantity,self:KeyInfoName(info))
       if hit then self:SnipeAlert(hit) end
      end
     end
     if debugprofilestop()-start>=3 then return false end
    end
    table.remove(round.pending,1);p=round.pending[1]
   end
   return true
  end,function()
   if s.round==round and round.complete and #round.pending==0 then self:SnipeRoundDone(round) end
  end)
 end
 done=function()
  if s.round~=round then return end
  if self.browseOwner~='snipe' then fail('Another search used the AH list; restarting');return end
  round.pages=round.pages+1
  local results=C_AuctionHouse.GetBrowseResults() or {}
  if #results<round.read then fail('AH list changed; restarting');return end
  round.pending[#round.pending+1]={results=results,from=round.read+1,to=#results};round.read=#results
  local A=C_AuctionHouse
  local more=A.HasFullBrowseResults and A.RequestMoreBrowseResults and not A.HasFullBrowseResults()
  if not (more and round.pages<MAX_PAGES and s.on and self:SnipeCanRun()
   and self:QueueRequest({id='snipe:more',kind='browsemore',priority=65,done=done,fail=fail})) then round.complete=true end
  read()
  if round.complete and #round.pending==0 and not self.jobs.snipe then self:SnipeRoundDone(round) end
 end
 if not self:QueueRequest({id='snipe',kind='browse',priority=20,
  query={searchString='',sorts={},filters={},itemClassFilters={}},done=done,fail=fail}) then
  s.round=nil;s.nextRound=GetTime()+ROUND_GAP
 end
end
-- Which request last started a browse (the AH keeps one browse list).
local origSend=M.SendAHRequest
function M:SendAHRequest(r)
 if r.kind=='browse' then self.browseOwner=r.id end
 return origSend(self,r)
end
function M:SnipeRoundDone(round)
 local s=state(self);if s.round~=round then return end
 s.round=nil;s.rounds=s.rounds+1;s.lastRound={items=round.items,pages=round.pages,seconds=GetTime()-round.started,at=time()}
 s.lastError=nil;s.nextRound=GetTime()+ROUND_GAP
 -- A hit no longer that cheap was bought (or cancelled): mark it gone and
 -- let the next mispost of the same item alert again.
 for _,h in ipairs(s.hits) do
  local now=round.seen[h.marketKey]
  if not h.gone and (now==nil or now>h.floor) then h.gone=true;h.status='GONE';s.alerted[h.marketKey]=nil end
 end
 self:RefreshUI()
end
M:RegisterHandler('AUCTION_HOUSE_CLOSED',function(self) if self.snipe and self.snipe.on then self:StopSnipe('Auction House closed') end end)

-- Shopping view ------------------------------------------------------------
function M:SnipeRows()
 local out={};for _,h in ipairs(state(self).hits) do if not h.gone then out[#out+1]=h end end
 for _,h in ipairs(state(self).hits) do if h.gone then out[#out+1]=h end end
 return out
end
function M:SnipeHitCount()
 local n=0;for _,h in ipairs(state(self).hits) do if not h.gone then n=n+1 end end;return n
end
function M:ShowSnipeHits()
 if self.ShopBuyClose then self:ShopBuyClose() end
 if self.StopTermSearch then self:StopTermSearch() end
 self.snipeView=true;self.shoppingListMode=false;self.shopFilters=nil;self.shopOnlyKey=nil;self.shopOnlyTerm=nil
 self.selectedRow=nil;self.shopScroll=0;self.shopSort={field='price',dir=1}
 self.shoppingSearchStatus='No misposts found yet. Turn on Snipe and keep the Auction House open.'
 -- The Shopping tab is the 'browse' view.
 if self.SetView and self.view~='browse' then pcall(self.SetView,self,'browse') end
 self:RefreshUI()
end
function M:SnipeStatus()
 local s=state(self)
 local bits={(s.on and '|cff40ff40Sniper ON|r' or 'Sniper off')}
 if s.round then bits[#bits+1]='page '..(s.round.pages+1)
 elseif s.lastRound then bits[#bits+1]=('pass: %d items, %ds'):format(s.lastRound.items,math.floor(s.lastRound.seconds+0.5)) end
 bits[#bits+1]=self:SnipeHitCount()..' live hit'..(self:SnipeHitCount()==1 and '' or 's')
 if s.lastError then bits[#bits+1]='|cffff8060'..s.lastError..'|r' end
 return table.concat(bits,'  |  ')
end
-- Any other Shopping search leaves the hits view.
for _,name in ipairs({'ShopSearch','OpenShoppingList','SearchListTerm','SearchListEntry','CollapseShoppingList'}) do
 local orig=M[name]
 if orig then M[name]=function(self,...)
  if self.snipeView then self.snipeView=false;self.shoppingSearchStatus=nil end
  return orig(self,...)
 end end
end
local origRows=M.ShoppingResultRows
function M:ShoppingResultRows()
 if self.snipeView then return self:SnipeRows() end
 return origRows(self)
end

-- /vmm snipe ...
function M:SnipeCommand(arg)
 arg=tostring(arg or ''):lower():match('^%s*(.-)%s*$')
 if arg=='' then self:ToggleSnipe();if state(self).on then self:ShowSnipeHits() end;return end
 if arg=='on' then if self:StartSnipe() then self:ShowSnipeHits() end;return end
 if arg=='off' then self:StopSnipe();return end
 if arg=='hits' then self:ShowSnipeHits();return end
 if arg=='sound' then self.db.settings.snipeSound=self.db.settings.snipeSound==false and true or false
  self:Print('Snipe sound '..(self.db.settings.snipeSound==false and 'off' or 'on'));return end
 local p=arg:match('^pct%s+(%d+)%%?$')
 if p then p=tonumber(p)
  if p<5 or p>90 then self:Print('Snipe percent must be 5-90');return end
  self.db.settings.snipePercent=p;self:Print('Sniper flags items at '..p..'% of their average or less');self:RefreshUI();return end
 local v=arg:match('^min%s+(%S+)$')
 if v then local c=self:ParseMoneyText(v)
  if not c then self:Print('Use an amount like 50s, 1g or 2g50s');return end
  self.db.settings.snipeMinGain=c;self:Print('Sniper minimum gain: '..self:Coins(c));self:RefreshUI();return end
 self:Print('/vmm snipe [on|off|hits|sound] | /vmm snipe pct 40 | /vmm snipe min 1g')
end

-- Snipe settings as dropdowns (1.23.2) ---------------------------------------
-- Shown on the Hits view's bottom bar in place of Flip Ledger / Export Results.
M.SNIPE_PCT_CHOICES={30,40,50,60,70}
M.SNIPE_MIN_CHOICES={1000,2500,5000,10000,20000,50000} -- 10s 25s 50s 1g 2g 5g
local DIM='|cff8f8f8f'
-- A button that opens a small list above it; picking a line calls set(value).
function M:SnipeDropdown(parent,x,y,w,title,choices,text,get,set)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,24)
 local menu=self.panel(parent,0,0,w,#choices*22+10);menu:ClearAllPoints();menu:SetPoint('BOTTOMLEFT',b,'TOPLEFT',0,2)
 if menu.SetFrameStrata then menu:SetFrameStrata('DIALOG') end;menu:Hide()
 menu.lines={}
 for i,v in ipairs(choices) do
  local l=CreateFrame('Button',nil,menu);l:SetPoint('TOPLEFT',5,-5-(i-1)*22);l:SetSize(w-10,22)
  l:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  l.text=l:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');l.text:SetPoint('LEFT',8,0);l.text:SetText(text(v))
  l.value=v
  l:SetScript('OnClick',function() menu:Hide();set(v);self:RefreshUI() end)
  menu.lines[i]=l
 end
 b.menu=menu;b.title=title;b.get=get;b.fmt=text
 b:SetScript('OnClick',function() if menu:IsShown() then menu:Hide() else menu:Show() end end)
 b:SetScript('OnHide',function() menu:Hide() end)
 return b
end
function M:InitSnipeControls(s)
 s.snipePct=self:SnipeDropdown(s,600,-524,128,'Flag at',self.SNIPE_PCT_CHOICES,
  function(v) return v..'% of normal or less' end,
  function() return self:SnipePercent() end,
  function(v) self.db.settings.snipePercent=v end)
 s.snipeMin=self:SnipeDropdown(s,732,-524,140,'Min profit',self.SNIPE_MIN_CHOICES,
  function(v) return self:Coins(v)..' profit or more' end,
  function() return self:SnipeMinGain() end,
  function(v) self.db.settings.snipeMinGain=v end)
 s.snipeSound=CreateFrame('Button',nil,s,'UIPanelButtonTemplate');s.snipeSound:SetPoint('TOPLEFT',876,-524);s.snipeSound:SetSize(128,24)
 s.snipeSound:SetScript('OnClick',function() self.db.settings.snipeSound=self.db.settings.snipeSound==false and true or false;self:RefreshUI() end)
end
function M:RenderSnipeControls(s,buying)
 if not s.snipePct then return end
 local on=self.snipeView and not buying
 for _,b in ipairs({s.snipePct,s.snipeMin,s.snipeSound}) do b:SetShown(on and true or false) end
 if s.flipLedger then s.flipLedger:SetShown(not on and not buying) end
 if s.exportResults then s.exportResults:SetShown(not on and not buying) end
 if s.status and s.status.SetWidth then s.status:SetWidth(on and 290 or 430) end
 if not on then return end
 s.snipePct:SetText('Flag: '..self:SnipePercent()..'% or less')
 s.snipeMin:SetText('Min profit: '..self:Coins(self:SnipeMinGain()))
 s.snipeSound:SetText('Sound: '..(self.db.settings.snipeSound==false and 'Off' or 'On'))
 for _,b in ipairs({s.snipePct,s.snipeMin}) do
  local cur=b.get()
  for _,l in ipairs(b.menu.lines) do l.text:SetText((l.value==cur and '|cff40ff40> ' or '  ')..b.fmt(l.value)..(l.value==cur and '|r' or '')) end
 end
end
