local _,M=...
-- Sale alerts (1.22): "A buyer has been found for your auction of X" arrives
-- the moment something sells, AH open or not. Work out what it sold for (your
-- listing price) and what you paid (Flip Ledger), play a coin sound, show it
-- on screen, and send it to the synced partner so the other character sees it
-- too. Exact amounts still come from the sale mail an hour later.

local function trim(s) return (tostring(s or ''):match('^%s*(.-)%s*$')) end
local function lower(s) return tostring(s or ''):lower() end

function M:SoldAuctionName(msg)
 if type(msg)~='string' then return nil end
 local template=ERR_AUCTION_SOLD_S or 'A buyer has been found for your auction of %s.'
 local prefix,suffix=template:match('^(.-)%%s(.*)$');if not prefix then return nil end
 prefix=prefix:gsub('(%W)','%%%1');suffix=suffix:gsub('(%W)','%%%1')
 local name=msg:match('^'..prefix..'(.-)'..suffix..'$')
 if name and name:find('|h',1,true) then name=name:match('%[(.-)%]') or name end
 name=trim(name)
 return name~='' and name or nil
end

-- One of your current auctions for this item (exact name first, then a base
-- name match); each sale claims a different listing.
local function claimListing(self,name,auctionID)
 -- Live rows from Listings, else the snapshot saved last time they loaded
 -- (so a /reload or a fresh login still knows your listing prices).
 -- 1.22.23: ownedRows starts each session as an empty list, so "live or
 -- snapshot" always picked the empty list and alerts at login had no price.
 -- Search both: this session's rows first, then the saved ones.
 local snap=self.db.ownedSnapshot
 local rows,seen={},{}
 for _,list in ipairs({self.ownedRows or {},type(snap)=='table' and type(snap.rows)=='table' and snap.rows or {}}) do
  for _,o in ipairs(list) do
   local id=o.auctionID
   if not (id and seen[id]) then if id then seen[id]=true end;rows[#rows+1]=o end
  end
 end
 self.saleClaimed=self.saleClaimed or {}
 -- The AH notification can name the exact auction: use it when it does.
 if auctionID then
  for _,o in ipairs(rows) do
   if o.auctionID==auctionID and self:Finite(o.unit,1,1e12) then self.saleClaimed[auctionID]=true;return o end
  end
 end
 -- By name: exact, then base name; a row already shown as SOLD is the likeliest
 -- match, then your other listings of it.
 for pass=1,4 do
  local wantSold=pass==1 or pass==3
  for _,o in ipairs(rows) do
   local id=o.auctionID or o
   local sold=self.OwnedSold and self:OwnedSold(o) or false
   if not self.saleClaimed[id] and sold==wantSold and self:Finite(o.unit,1,1e12)
    and (pass<=2 and lower(o.name)==lower(name) or pass>=3 and self:NameScore(o.name,name)==1) then
    self.saleClaimed[id]=true;return o
   end
  end
 end
end

function M:BuildSaleAlert(name,auctionID,link)
 local cut=tonumber(self.db.settings.ahCut) or 0.05;if not self:Finite(cut,0,0.3) then cut=0.05 end
 local a={name=name,qty=1}
 local o=claimListing(self,name,auctionID)
 local flip=self.HeldFlip and self:HeldFlip(name,link,o and o.marketKey)
 if o then a.qty=math.max(1,math.floor(tonumber(o.quantity) or 1));a.gross=math.floor(o.unit*a.qty+0.5)
 elseif flip and flip.listPrice then a.qty=1;a.gross=flip.listPrice
 else
  -- Last price you posted this item at with Market. Stacks (cloth etc.) can
  -- sell in part, so for those only the price each is known.
  local key=type(link)=='string' and link:find('item:',1,true) and self.LinkIdentity and self:LinkIdentity(link) or nil
  local keys={}
  if flip and flip.key~=nil then keys[#keys+1]=flip.key end
  if key~=nil then keys[#keys+1]=key end
  local byName=self.UniqueMarketByName and self:UniqueMarketByName(name);if byName~=nil then keys[#keys+1]=byName end
  local h
  for _,k in ipairs(keys) do
   local list=type(self.db.postHistory)=='table' and self.db.postHistory[k]
   -- A key shared by several suffixes: only trust it when the scan says so.
   local m=self.db.market[k]
   if type(list)=='table' and list[1] and not (m and m.mixedVariants) then h=list[1];key=k;break end
  end
  key=key or keys[1]
  if h and self:Finite(h.unit,1,1e12) then
   if (tonumber(h.quantity) or 1)<=1 then a.qty=1;a.gross=math.floor(h.unit)
   else a.unit=math.floor(h.unit);a.qty=nil end
  elseif key~=nil and self.StoredPriceObservation then
   -- Last resort: the current market price, clearly marked as an estimate.
   -- Never another suffix's price (see VariantPrice in Tooltips.lua).
   local state,sf=self:VariantPrice(key,name,self:LinkName(link))
   local p=state=='suffix' and {floor=sf.floor} or state=='key' and self:StoredPriceObservation(key) or nil
   if p and self:Finite(p.floor,1,1e12) then a.unit=math.floor(p.floor);a.qty=nil;a.estimate=true end
  end
 end
 if a.gross then a.net=math.floor(a.gross*(1-cut)+0.5) end
 if flip and flip.cost then
  a.paid=math.floor(flip.cost/math.max(1,flip.qty or 1)*a.qty+0.5)
  -- The listing deposit comes back with the sale, so it is not a cost here.
  if a.net then a.profit=a.net-a.paid end
 end
 return a
end

function M:SaleAlertText(a,from)
 local who=from and ('|cffc8a0ff'..from..':|r ') or ''
 local item=a.qty and a.qty>1 and (a.name..' x'..a.qty) or a.name
 if not a.gross and a.unit and a.estimate then return who..'Sold '..a.name..' - about '..self:Coins(a.unit)..' each (market price)' end
 if not a.gross and a.unit then return who..'Sold '..a.name..' at '..self:Coins(a.unit)..' each (your last post)' end
 if not a.gross then return who..'Sold '..item..' (price shows when the mail arrives)' end
 local text=who..'Sold '..item..' for '..self:Coins(a.gross)..' - you get '..self:Coins(a.net)
 if a.profit then
  local pct=self:FlipPercentText(a.profit,a.paid)
  text=text..(a.profit>=0 and (' | flipped for |cff40ff40+'..self:Coins(a.profit)..(pct and (' ('..pct..')') or '')..'|r') or (' | |cffff6060loss '..self:Coins(-a.profit)..(pct and (' ('..pct..')') or '')..'|r'))
   ..' (paid '..self:Coins(a.paid)..')'
 end
 return text
end

M.SALE_CHIME='Interface\\AddOns\\VoidMarkMarket\\Media\\LockChime.ogg'
-- The chime (Media\LockChime.ogg); the game's coin sound if the file can't play.
function M:PlaySaleSound()
 local played,why=false,nil
 if PlaySoundFile then
  local ok,willPlay=pcall(PlaySoundFile,self.SALE_CHIME,'Master')
  played=ok and willPlay~=false and willPlay~=nil
  if not ok then why='error: '..tostring(willPlay) elseif not played then why='the game could not find or play the file' end
 else why='PlaySoundFile is not available on this client' end
 local coin=false
 if not played and PlaySound then
  local id=SOUNDKIT and (SOUNDKIT.LOOT_WINDOW_COIN_SOUND or SOUNDKIT.IG_BACKPACK_COIN_OK) or 120
  local ok,res=pcall(PlaySound,id,'Master');coin=ok and res~=false
 end
 self.lastSoundResult={chime=played,coin=coin,why=why,at=time()}
 return played
end
-- /vmm testsound and the Settings "Test sound" button: play it and say what happened.
function M:TestSaleSound()
 self:PlaySaleSound();local r=self.lastSoundResult or {}
 local master=GetCVar and tonumber(GetCVar('Sound_MasterVolume'))
 local enabled=GetCVar and GetCVar('Sound_EnableAllSound')
 local bg=GetCVar and GetCVar('Sound_EnableSoundWhenGameIsInBG')
 if r.chime then self:Print('Sale sound: chime played (Master channel, volume '..tostring(master and math.floor(master*100+0.5)..'%' or '?')..').')
 else
  self:Print('Sale sound: chime did NOT play ('..tostring(r.why)..'). '..(r.coin and 'Coin sound played instead.' or 'Coin sound also failed.'))
  self:Print('  Check that Interface\\AddOns\\VoidMarkMarket\\Media\\LockChime.ogg exists, then fully restart WoW (a /reload does not find new files).')
 end
 if enabled=='0' then self:Print('  All game sound is turned off (System > Sound > Enable Sound).') end
 if master and master<=0 then self:Print('  Master volume is 0.') end
 if bg=='0' then self:Print('  "Sound in Background" is off: nothing plays while WoW is not the focused window.') end
 local quiet=self:SaleSoundQuietHere()
 if self.db.settings.saleAlertSound==false then self:Print('  Note: Sale sound is switched off in Settings, so real sales are silent.')
 elseif quiet then self:Print('  Note: this character is quiet while your partner is online (Quiet when partner online).') end
 return r
end
-- "Quiet when partner is online": this character stays silent while the synced
-- character is online, so only one chime plays. Default: on for Voidmark Bank.
function M:SaleSoundQuietHere()
 local v=self.db.settings.saleSoundQuietWithPartner
 if v==nil then v=self.IsBankCharacter and self:IsBankCharacter() or false end
 return v and self.PartnerOnline and self:PartnerOnline() or false
end
-- Message (banner + chat) and sound switch on and off separately in Settings.
function M:ShowSaleAlert(a,from)
 local message=self.db.settings.saleAlerts~=false
 local sound=self.db.settings.saleAlertSound~=false and not self:SaleSoundQuietHere()
 if not message and not sound then return end
 local text=self:SaleAlertText(a,from)
 if sound then self:PlaySaleSound() end
 if not message then self.lastSaleAlert={text=text,at=time()};return end
 pcall(self.SaleToast,self,a,from,text)
 self:Print(text)
 self.lastSaleAlert={text=text,at=time()}
end

-- Purple sale banner (1.22.7), styled like VoidMark Taunt's flash: dark void
-- panel, purple border, small bright label, centered text, fades after 6s.
-- Several sales stack downward. Drag any banner to move them; position saved.
local VOID={bg={0.015,0.010,0.025,0.88},purple={0.46,0.13,0.72,1},bright={0.72,0.35,1,1},
 text={0.94,0.91,0.98,1},muted={0.62,0.56,0.68,1},gain={0.30,0.89,0.42,1},loss={1,0.38,0.38,1}}
local SHOW,FADE,MAXTOASTS,W=6,1.5,4,380
local function anchor(self)
 local a=self.saleToastAnchor;if a then return a end
 a=CreateFrame('Frame','VoidMarkMarketSaleAnchor',UIParent);a:SetSize(W,1)
 a:SetFrameStrata('FULLSCREEN_DIALOG');a:SetMovable(true);a:SetClampedToScreen(true)
 local pos=self.db.settings.saleAlertPos
 a:ClearAllPoints()
 if type(pos)=='table' and type(pos[1])=='string' and self:Finite(pos[2],-5000,5000) and self:Finite(pos[3],-5000,5000) then
  a:SetPoint(pos[1],UIParent,pos[1],pos[2],pos[3])
 else a:SetPoint('CENTER',UIParent,'CENTER',0,115) end
 self.saleToastAnchor=a;return a
end
local function makeToast(self)
 local f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');f:SetSize(W,62)
 f:SetFrameStrata('FULLSCREEN_DIALOG');f:EnableMouse(true)
 if f.SetBackdrop then
  f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
  f:SetBackdropColor(unpack(VOID.bg))
 end
 local function fs(font,y,color)
  local t=f:CreateFontString(nil,'OVERLAY',font);t:SetPoint('TOP',0,y);t:SetWidth(W-16);t:SetJustifyH('CENTER')
  if t.SetWordWrap then t:SetWordWrap(false) end;t:SetTextColor(unpack(color));return t
 end
 f.label=fs('GameFontNormalSmall',-6,VOID.bright)
 f.item=fs('GameFontHighlight',-20,VOID.text)
 f.detail=fs('GameFontHighlightSmall',-38,VOID.muted)
 f.profit=fs('GameFontNormalLarge',-54,VOID.gain)
 if f.RegisterForDrag then f:RegisterForDrag('LeftButton') end
 f:SetScript('OnDragStart',function() anchor(self):StartMoving() end)
 f:SetScript('OnDragStop',function()
  local a=anchor(self);a:StopMovingOrSizing()
  local point,_,_,x,y=a:GetPoint()
  if not self.persistenceBlocked and point then self.db.settings.saleAlertPos={point,math.floor((x or 0)+0.5),math.floor((y or 0)+0.5)} end
 end)
 f:SetScript('OnUpdate',function(t)
  if not t.expiresAt then return end
  local now=GetTime()
  if now<=t.expiresAt then t:SetAlpha(1);return end
  local gone=now-t.expiresAt
  if gone>=FADE then t.expiresAt=nil;t:Hide();t:SetAlpha(1);self:LayoutSaleToasts();return end
  t:SetAlpha(1-gone/FADE)
 end)
 f:Hide();return f
end
function M:LayoutSaleToasts()
 local a=anchor(self);local y=0
 for _,t in ipairs(self.saleToasts or {}) do
  if t:IsShown() then t:ClearAllPoints();t:SetPoint('TOP',a,'TOP',0,y);y=y-(t:GetHeight()+6) end
 end
end
function M:SaleToast(a,from)
 self.saleToasts=self.saleToasts or {}
 -- Reuse the oldest banner when all are showing.
 local t
 for _,x in ipairs(self.saleToasts) do if not x:IsShown() then t=x;break end end
 if not t then
  if #self.saleToasts<MAXTOASTS then t=makeToast(self);self.saleToasts[#self.saleToasts+1]=t
  else t=table.remove(self.saleToasts,1);self.saleToasts[#self.saleToasts+1]=t end
 else
  for i,x in ipairs(self.saleToasts) do if x==t then table.remove(self.saleToasts,i);break end end
  self.saleToasts[#self.saleToasts+1]=t
 end
 local flip=a.profit~=nil
 t.label:SetText(from and (tostring(from):upper()..' SOLD') or 'SOLD')
 t.item:SetText((a.qty and a.qty>1) and (a.name..' x'..a.qty) or a.name)
 local detail
 if a.gross then detail='Sold '..self:Coins(a.gross)..'  ·  you get '..self:Coins(a.net or a.gross)..(a.paid and ('  ·  paid '..self:Coins(a.paid)) or '')
 elseif a.unit and a.estimate then detail='About '..self:Coins(a.unit)..' each (market price)'
 elseif a.unit then detail='Sold at '..self:Coins(a.unit)..' each (your last post)'
 else detail='Price shows when the sale mail arrives' end
 t.detail:SetText(detail)
 if flip then
  local pct=self:FlipPercentText(a.profit,a.paid)
  t.profit:SetText((a.profit>=0 and '+' or '-')..self:Coins(math.abs(a.profit))..(a.profit>=0 and ' flip' or ' loss')..(pct and ('  '..pct) or ''))
  t.profit:SetTextColor(unpack(a.profit>=0 and VOID.gain or VOID.loss));t.profit:Show();t:SetHeight(78)
 else t.profit:SetText('');t.profit:Hide();t:SetHeight(58) end
 if t.SetBackdropBorderColor then t:SetBackdropBorderColor(unpack(flip and VOID.bright or VOID.purple)) end
 t.expiresAt=GetTime()+SHOW;t:SetAlpha(1);t:Show()
 self:LayoutSaleToasts()
 return t
end

-- The same sale can be reported by both the AH notification and a chat line;
-- count it once. Two real sales from the same source are never merged.
-- Returns true when the OTHER source reported this within 5 seconds.
local function recent(self,kind,name,source)
 local now=GetTime and GetTime() or 0;local base=kind..'|'..tostring(name):lower()
 self.recentAHNotices=self.recentAHNotices or {}
 local other=self.recentAHNotices[base..'|'..(source=='chat' and 'ah' or 'chat')]
 if other and now-other<5 then self.recentAHNotices[base..'|'..(source=='chat' and 'ah' or 'chat')]=nil;return true end
 self.recentAHNotices[base..'|'..source]=now
 return false
end
M.RecentAHNotice=recent
-- Local sale: show it here and queue it for the partner.
function M:HandleAuctionSold(msg,itemName,auctionID,link)
 local name=itemName or self:SoldAuctionName(msg);if not name or not self.db then return false end
 if recent(self,'sold',name,itemName and 'ah' or 'chat') then return true end
 local a=self:BuildSaleAlert(name,auctionID,link)
 self:ShowSaleAlert(a)
 if self.db.syncPeer and self.db.settings.saleAlertsShare~=false and self.shareRun then
  local r=self.shareRun;r.alerts=r.alerts or {}
  if #r.alerts<20 then
   self.saleAlertSeq=(self.saleAlertSeq or 0)+1
   r.alerts[#r.alerts+1]={id=tostring(time())..'-'..self.saleAlertSeq,a=a,at=GetTime()}
  end
 end
 return true
end
M:RegisterHandler('CHAT_MSG_SYSTEM',function(self,_,msg) self:HandleAuctionSold(msg) end)
-- Forever's AH reports sales and wins with AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION
-- (notification, item text, auction ID); the chat frame prints it itself, so
-- no CHAT_MSG_SYSTEM ever fires for them. Enum.AuctionHouseNotification:
-- 2 = AuctionWon, 4 = AuctionSold, 5 = AuctionExpired.
function M:HandleAHNotification(notification,text,auctionID)
 local N=Enum and Enum.AuctionHouseNotification or {}
 local sold,won=N.AuctionSold or 4,N.AuctionWon or 2
 if type(text)~='string' or text=='' then return false end
 local name=text:match('%[(.-)%]') or text
 name=name:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''):match('^%s*(.-)%s*$')
 if name=='' then return false end
 if notification==sold then return self:HandleAuctionSold(nil,name,tonumber(auctionID),text) end
 if notification==won and self.ResolveWonAuction then
  if recent(self,'won',name,'ah') then return true end
  local template=ERR_AUCTION_WON_S or 'You won an auction for %s'
  return self:ResolveWonAuction(template:format(name))
 end
 return false
end
-- Load your auctions a few seconds after the AH opens, so sale alerts know
-- your listing prices without opening Listings first.
M:RegisterHandler('AUCTION_HOUSE_SHOW',function(self)
 if not (C_Timer and C_Timer.After) then return end
 C_Timer.After(4,function()
  if self.ahOpen and self.db and self.RequestOwnedAuctionsDiagnostic and not self.ownedLoadedAt then pcall(self.RequestOwnedAuctionsDiagnostic,self) end
 end)
end)
M:RegisterHandler('AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION',function(self,_,notification,text,auctionID) self:HandleAHNotification(notification,text,auctionID) end)

-- Wire format for the partner (sent by Sharing): N, epoch, id, name, qty, gross, net, paid
local function enc(s) return (tostring(s):gsub('[%%%c,;|/\t]',function(c) return ('%%%02X'):format(c:byte()) end)) end
local function dec(s) return (tostring(s):gsub('%%(%x%x)',function(x) return string.char(tonumber(x,16)) end)) end
function M:EncodeSaleAlert(epoch,item)
 local a=item.a
 -- qty 0 = only the price each is known (a stack that may have sold in part).
 if not a.gross and a.unit then return table.concat({'N',epoch,item.id,enc(a.name),a.estimate and 0 or 0,a.unit,a.estimate and 1 or 0,-1},'\t') end
 return table.concat({'N',epoch,item.id,enc(a.name),a.qty or 1,a.gross or 0,a.net or 0,a.paid or -1},'\t')
end
function M:ReceiveSaleAlert(f,sender)
 if #f<9 then return end
 local id=f[4];local name=dec(f[5])
 local qty,gross,net,paid=tonumber(f[6]),tonumber(f[7]),tonumber(f[8]),tonumber(f[9])
 if type(id)~='string' or #id>40 or name=='' or #name>80 or not self:Finite(qty,0,1e6) then return end
 self.seenSaleAlerts=self.seenSaleAlerts or {}
 if self.seenSaleAlerts[id] then return true end
 self.seenSaleAlerts[id]=true
 local a={name=name,qty=qty}
 if qty==0 then a.qty=nil;if self:Finite(gross,1,1e12) then a.unit=gross;a.estimate=net==1 end
 elseif self:Finite(gross,1,1e12) then a.gross=gross;a.net=self:Finite(net,0,1e12) and net or nil end
 if self:Finite(paid,0,1e12) then a.paid=paid;if a.net then a.profit=a.net-paid end end
 local who=type(sender)=='string' and sender:match('^([^%-]+)') or 'Partner'
 self:ShowSaleAlert(a,who)
 return true
end

-- Profit as a percentage of what you paid: paid 2s 50c, profit 7s = +280%.
function M:FlipPercentText(profit,paid)
 if not (self:Finite(profit,-1e12,1e12) and self:Finite(paid,1,1e12)) then return nil end
 local x=profit*100/paid;local p=x>=0 and math.floor(x+0.5) or -math.floor(-x+0.5)
 return (p>=0 and '+' or '')..p..'%'
end
