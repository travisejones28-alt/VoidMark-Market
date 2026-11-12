local _,M=...
-- Sale alerts (1.22): "A buyer has been found for your auction of X" arrives
-- the moment something sells, AH open or not. Work out what it sold for (your
-- listing price) and what you paid (Flip Ledger), play a coin sound, show it
-- on screen, and send it to the synced partner so the other character sees it
-- too. Exact amounts still come from the sale mail an hour later.

local function trim(s) return (tostring(s or ''):match('^%s*(.-)%s*$')) end
local function lower(s) return tostring(s or ''):lower() end
local function sameItem(a,b)
 a,b=lower(a),lower(b)
 if a=='' or b=='' then return false end
 return a==b or a:sub(1,#b)==b or b:sub(1,#a)==a
end

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
local function claimListing(self,name)
 local rows=self.ownedRows or {}
 self.saleClaimed=self.saleClaimed or {}
 for pass=1,2 do
  for _,o in ipairs(rows) do
   local id=o.auctionID or o
   if not self.saleClaimed[id] and not (self.OwnedSold and self:OwnedSold(o)) and self:Finite(o.unit,1,1e12)
    and (pass==1 and lower(o.name)==lower(name) or pass==2 and sameItem(o.name,name)) then
    self.saleClaimed[id]=true;return o
   end
  end
 end
end

function M:BuildSaleAlert(name)
 local cut=tonumber(self.db.settings.ahCut) or 0.05;if not self:Finite(cut,0,0.3) then cut=0.05 end
 local a={name=name,qty=1}
 local o=claimListing(self,name)
 local flip=self.HeldFlip and self:HeldFlip(name)
 if o then a.qty=math.max(1,math.floor(tonumber(o.quantity) or 1));a.gross=math.floor(o.unit*a.qty+0.5)
 elseif flip and flip.listPrice then a.qty=1;a.gross=flip.listPrice end
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
 if not a.gross then return who..'Sold '..item..' (price shows when the mail arrives)' end
 local text=who..'Sold '..item..' for '..self:Coins(a.gross)..' - you get '..self:Coins(a.net)
 if a.profit then
  text=text..(a.profit>=0 and (' | flipped for |cff40ff40+'..self:Coins(a.profit)..'|r') or (' | |cffff6060loss '..self:Coins(-a.profit)..'|r'))
   ..' (paid '..self:Coins(a.paid)..')'
 end
 return text
end

function M:ShowSaleAlert(a,from)
 if self.db.settings.saleAlerts==false then return end
 local text=self:SaleAlertText(a,from)
 if self.db.settings.saleAlertSound~=false and PlaySound then
  local coin=SOUNDKIT and (SOUNDKIT.LOOT_WINDOW_COIN_SOUND or SOUNDKIT.IG_BACKPACK_COIN_OK) or 120
  pcall(PlaySound,coin,'Master')
 end
 if RaidNotice_AddMessage and RaidWarningFrame then
  pcall(RaidNotice_AddMessage,RaidWarningFrame,text,{r=1,g=0.82,b=0.2})
 end
 self:Print(text)
 self.lastSaleAlert={text=text,at=time()}
end

-- Local sale: show it here and queue it for the partner.
function M:HandleAuctionSold(msg)
 local name=self:SoldAuctionName(msg);if not name or not self.db then return false end
 local a=self:BuildSaleAlert(name)
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

-- Wire format for the partner (sent by Sharing): N, epoch, id, name, qty, gross, net, paid
local function enc(s) return (tostring(s):gsub('[%%%c,;|/\t]',function(c) return ('%%%02X'):format(c:byte()) end)) end
local function dec(s) return (tostring(s):gsub('%%(%x%x)',function(x) return string.char(tonumber(x,16)) end)) end
function M:EncodeSaleAlert(epoch,item)
 local a=item.a
 return table.concat({'N',epoch,item.id,enc(a.name),a.qty or 1,a.gross or 0,a.net or 0,a.paid or -1},'\t')
end
function M:ReceiveSaleAlert(f,sender)
 if #f<9 then return end
 local id=f[4];local name=dec(f[5])
 local qty,gross,net,paid=tonumber(f[6]),tonumber(f[7]),tonumber(f[8]),tonumber(f[9])
 if type(id)~='string' or #id>40 or name=='' or #name>80 or not self:Finite(qty,1,1e6) then return end
 self.seenSaleAlerts=self.seenSaleAlerts or {}
 if self.seenSaleAlerts[id] then return true end
 self.seenSaleAlerts[id]=true
 local a={name=name,qty=qty}
 if self:Finite(gross,1,1e12) then a.gross=gross;a.net=self:Finite(net,0,1e12) and net or nil end
 if self:Finite(paid,0,1e12) then a.paid=paid;if a.net then a.profit=a.net-paid end end
 local who=type(sender)=='string' and sender:match('^([^%-]+)') or 'Partner'
 self:ShowSaleAlert(a,who)
 return true
end
