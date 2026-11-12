local _,M=...
-- Flip Ledger: every item you buy, what you paid and when, what you listed it
-- at, what it sold for and how long it took, plus summaries by item and by
-- suffix so you can see which flips actually make money.
--  * Buys: confirmed Market purchases, and buys made anywhere else (Blizzard
--    AH, other addons) from the "You won an auction" message + the bid sent.
--  * Listed: read from your auctions (Listings) whenever they refresh.
--  * Expired: "Auction expired" mail; the listing deposit counts as a loss.
--  * Sold: "Auction successful" invoices at the mailbox, matched to the
--    oldest unsold buy of the same item. Sales with no buy are kept too.
local MAX_ROWS=1500
local ROWS,ROW_H=17,22
local DAY=86400

function M:FlipBook()
 if type(self.db.flips)~='table' then self.db.flips={} end
 return self.db.flips
end
local function trimBook(self)
 local book=self:FlipBook()
 while #book>MAX_ROWS do
  local drop
  for i,f in ipairs(book) do if f.cost==nil or (f.sold or 0)>=(f.qty or 1) then drop=i;break end end
  table.remove(book,drop or 1)
 end
end
local function nameOf(link,name)
 if type(link)=='string' then local n=link:match('%[(.-)%]');if n and n~='' then return n end end
 return type(name)=='string' and name or nil
end
local function sameItem(a,b)
 a,b=tostring(a or ''):lower(),tostring(b or ''):lower()
 if a=='' or b=='' then return false end
 return a==b or a:sub(1,#b)==b or b:sub(1,#a)==a
end
-- Open (not fully sold) buys of an item, oldest first; exact name, then partial.
local function openFlips(self,name,key)
 local out,seen={},{}
 local _,kid,ks=self:ParseKey(key)
 for pass=1,2 do
  for _,f in ipairs(self:FlipBook()) do
   if not seen[f] and f.cost and (f.sold or 0)<(f.qty or 1) then
    local hit
    if pass==1 then
     hit=type(name)=='string' and tostring(f.name):lower()==name:lower()
     if not hit and kid and f.key~=nil then local _,id,s=self:ParseKey(f.key);hit=id==kid and (s or 0)==(ks or 0) end
    else hit=sameItem(f.name,name) end
    if hit then seen[f]=true;out[#out+1]=f end
   end
  end
 end
 return out
end

-- Recording ------------------------------------------------------------------
function M:RecordFlipBuy(p)
 if self.persistenceBlocked or type(p)~='table' or not self:Finite(p.cost,0,1e14) then return end
 local qty=tonumber(p.quantity) or 1;if qty<1 then return end
 local book=self:FlipBook()
 self.db.flipSequence=(tonumber(self.db.flipSequence) or 0)+1
 local f={id=self.db.flipSequence,name=nameOf(p.itemLink,p.name) or ('Item '..tostring(p.itemID)),key=p.marketKey,
  itemID=p.itemID,qty=qty,cost=math.floor(p.cost),at=tonumber(p.at) or time(),char=self.characterID,sold=0,gross=0,fee=0,
  source=p.source or 'Market'}
 book[#book+1]=f
 trimBook(self);self:RefreshUI();return f
end
function M:RecordFlipSale(name,qty,gross,fee)
 if self.persistenceBlocked or type(name)~='string' or name=='' or not self:Finite(gross,0,1e14) then return end
 qty=tonumber(qty) or 1;if qty<1 then qty=1 end
 fee=self:Finite(fee,0,gross) and fee or 0
 local left=qty
 for _,f in ipairs(openFlips(self,name)) do
  if left<=0 then break end
  local take=math.min((f.qty or 1)-(f.sold or 0),left)
  f.sold=(f.sold or 0)+take;f.gross=(f.gross or 0)+gross*take/qty;f.fee=(f.fee or 0)+fee*take/qty
  f.soldAt=time();left=left-take
 end
 if left>0 then
  local book=self:FlipBook()
  self.db.flipSequence=(tonumber(self.db.flipSequence) or 0)+1
  book[#book+1]={id=self.db.flipSequence,name=name,qty=left,cost=nil,at=time(),soldAt=time(),char=self.characterID,
   sold=left,gross=gross*left/qty,fee=fee*left/qty,source='Sale only'}
 end
 trimBook(self);self:RefreshUI()
end
-- "Auction expired: X" mail: the item came back and the deposit is gone.
function M:RecordFlipExpired(name)
 if self.persistenceBlocked or type(name)~='string' or name=='' then return end
 local f=openFlips(self,name)[1];if not f then return end
 f.expired=(f.expired or 0)+1
 f.depositsLost=(f.depositsLost or 0)+(tonumber(f.deposit) or 0)
 f.listPrice=nil;f.deposit=nil;f.listedAt=nil
 self:RefreshUI()
end
-- Your current auctions: note the listing price/deposit on the matching buy.
function M:UpdateFlipListings(rows)
 if self.persistenceBlocked then return end
 local claimed={}
 for _,o in ipairs(rows or {}) do
  if not (self.OwnedSold and self:OwnedSold(o)) and self:Finite(o.unit,1,1e12) then
   for _,f in ipairs(openFlips(self,o.name,o.marketKey)) do
    if not claimed[f] then
     claimed[f]=true
     if f.listPrice~=math.floor(o.unit) then f.listedAt=time() end
     f.listPrice=math.floor(o.unit);f.deposit=tonumber(o.deposit) or f.deposit
     break
    end
   end
  end
 end
end
-- Buys made outside Market: remember each bid sent, then the "won" message
-- names the item. Market's own purchases are skipped (they have an order).
function M:NoteOutsideBid(auctionID,amount)
 local x=self.execution
 if x and x.state=='pending' and x.live and x.live.auctionID==auctionID then return end
 if not self:Finite(amount,1,1e14) then return end
 self.outsideBids=self.outsideBids or {}
 table.insert(self.outsideBids,{id=auctionID,amount=math.floor(amount),at=GetTime and GetTime() or 0})
 while #self.outsideBids>10 do table.remove(self.outsideBids,1) end
end
function M:RecordOutsideBuy(name)
 local bids=self.outsideBids;if not bids or #bids==0 then return false end
 local now=GetTime and GetTime() or 0
 local bid=table.remove(bids,1)
 while bid and now-bid.at>120 do bid=table.remove(bids,1) end
 if not bid then return false end
 self:RecordFlipBuy({name=name,quantity=1,cost=bid.amount,source='AH'})
 return true
end
function M:HookOutsideBids()
 if self.outsideBidHooked or not hooksecurefunc or not C_AuctionHouse or not C_AuctionHouse.PlaceBid then return end
 self.outsideBidHooked=true
 hooksecurefunc(C_AuctionHouse,'PlaceBid',function(id,amount) pcall(self.NoteOutsideBid,self,id,amount) end)
end
M:RegisterHandler('AUCTION_HOUSE_SHOW',function(self) self:HookOutsideBids() end)

-- Numbers ---------------------------------------------------------------------
function M:FlipNumbers(f)
 local qty=f.qty or 1;local sold=f.sold or 0
 local net=(f.gross or 0)-(f.fee or 0)
 local lost=tonumber(f.depositsLost) or 0
 local soldCost=f.cost and f.cost*sold/qty or nil
 local profit=(sold>0 and soldCost) and math.floor(net-soldCost-lost+0.5) or nil
 local days=(sold>0 and f.cost and f.soldAt and f.at) and math.max(0,(f.soldAt-f.at)/DAY) or nil
 local status
 if f.cost==nil then status='Sold (no buy record)'
 elseif sold>=qty then status='Sold'
 elseif sold>0 then status='Sold '..sold..'/'..qty
 elseif f.listPrice then status='Listed'
 else status='Holding' end
 if (f.expired or 0)>0 and sold<qty then status=status..' (expired x'..f.expired..')' end
 return {net=math.floor(net+0.5),profit=profit,status=status,open=f.cost and qty-sold or 0,days=days,lost=lost,
  roi=(profit and soldCost and soldCost>0) and profit/soldCost or nil}
end
local function inPeriod(f,period)
 if period=='today' then
  local t=date and date('*t') or nil
  local start=t and time({year=t.year,month=t.month,day=t.day,hour=0}) or time()-DAY
  return (f.soldAt or f.at or 0)>=start or (f.at or 0)>=start
 elseif period=='week' then return (f.soldAt or f.at or 0)>=time()-7*DAY or (f.at or 0)>=time()-7*DAY end
 return true
end
function M:FlipTotals(period)
 local t={spent=0,net=0,profit=0,holding=0,holdingCost=0,sold=0,lost=0,listedValue=0}
 for _,f in ipairs(self:FlipBook()) do
  if inPeriod(f,period) then
   local n=self:FlipNumbers(f)
   if f.cost then t.spent=t.spent+f.cost end
   t.net=t.net+n.net;t.lost=t.lost+n.lost
   if n.profit then t.profit=t.profit+n.profit;t.sold=t.sold+(f.sold or 0) end
   if n.open>0 then
    t.holding=t.holding+n.open;t.holdingCost=t.holdingCost+f.cost*n.open/(f.qty or 1)
    if f.listPrice then t.listedValue=t.listedValue+f.listPrice*n.open end
   end
  end
 end
 t.holdingCost=math.floor(t.holdingCost+0.5)
 return t
end
function M:FlipRows(filter,period)
 local out={}
 for _,f in ipairs(self:FlipBook()) do
  local n=self:FlipNumbers(f)
  local keep=filter=='holding' and n.open>0 or filter=='sold' and (f.sold or 0)>0 or (filter~='holding' and filter~='sold')
  if keep and inPeriod(f,period) then out[#out+1]=f end
 end
 table.sort(out,function(a,b) return (a.soldAt or a.at or 0)>(b.soldAt or b.at or 0) end)
 return out
end
-- "Buccaneer's Gloves of Healing" -> "of Healing"; "of the Monkey" kept whole.
function M:FlipSuffix(name)
 name=tostring(name or '')
 return name:match(' (of the %a+)$') or name:match(' (of %a+)$') or 'No suffix'
end
-- Summary rows grouped by item name or by suffix.
function M:FlipGroups(by,period)
 local groups,order={},{}
 for _,f in ipairs(self:FlipBook()) do
  if f.cost and inPeriod(f,period) then
   local g=by=='suffix' and self:FlipSuffix(f.name) or f.name
   local s=groups[g]
   if not s then s={name=g,bought=0,sold=0,paid=0,soldPaid=0,net=0,profit=0,days=0,daysN=0,holding=0,expired=0};groups[g]=s;order[#order+1]=s end
   local n=self:FlipNumbers(f);local qty=f.qty or 1
   s.bought=s.bought+qty;s.paid=s.paid+f.cost;s.expired=s.expired+(f.expired or 0);s.holding=s.holding+n.open
   if (f.sold or 0)>0 then
    s.sold=s.sold+f.sold;s.soldPaid=s.soldPaid+f.cost*f.sold/qty;s.net=s.net+n.net;s.profit=s.profit+(n.profit or 0)
    if n.days then s.days=s.days+n.days;s.daysN=s.daysN+1 end
   end
  end
 end
 for _,s in ipairs(order) do
  s.avgPaid=s.bought>0 and math.floor(s.paid/s.bought+0.5) or nil
  s.avgSold=s.sold>0 and math.floor(s.net/s.sold+0.5) or nil
  s.roi=s.soldPaid>0 and s.profit/s.soldPaid or nil
  s.avgDays=s.daysN>0 and s.days/s.daysN or nil
 end
 return order
end
function M:RemoveFlip(id)
 local book=self:FlipBook()
 for i=#book,1,-1 do if book[i].id==id then table.remove(book,i) end end
 self:RefreshUI()
end
function M:FlipLedgerCSV()
 local lines={'Item,Quantity,Paid,Bought,Listed,Sold for,Sold,Days,Deposits lost,Profit,Status,Source'}
 local function d(t) return t and date and date('%Y-%m-%d %H:%M',t) or '' end
 for _,f in ipairs(self:FlipRows('all')) do
  local n=self:FlipNumbers(f)
  lines[#lines+1]=table.concat({'"'..tostring(f.name):gsub('"','""')..'"',f.qty or 1,f.cost or '',d(f.at),f.listPrice or '',
   (f.sold or 0)>0 and n.net or '',d(f.soldAt),n.days and ('%.1f'):format(n.days) or '',n.lost,n.profit or '',n.status,f.source or ''},',')
 end
 return table.concat(lines,'\n')
end

-- Ctrl + hover: what you last paid -------------------------------------------
function M:BoughtHistory(link)
 local name=nameOf(link);local key=self.LinkIdentity and self:LinkIdentity(link)
 local _,kid,ks=self:ParseKey(key)
 local out={}
 local function same(nm,k)
  if name and type(nm)=='string' and nm:lower()==name:lower() then return true end
  if kid and k~=nil then local _,id,s=self:ParseKey(k);return id==kid and (s or 0)==(ks or 0) end
  return false
 end
 for _,f in ipairs(self:FlipBook()) do
  if f.cost and same(f.name,f.key) then out[#out+1]={cost=f.cost,qty=f.qty or 1,at=f.at,sold=f.sold or 0,net=self:FlipNumbers(f).net,soldAt=f.soldAt,char=f.char} end
 end
 if #out==0 then -- buys from before the Flip Ledger
  for _,e in ipairs(self.db.ledger or {}) do
   if e.kind=='purchase' and e.status=='confirmed' and self:Finite(e.cost,0,1e14) and same(nameOf(e.itemLink,e.name),e.marketKey) then
    out[#out+1]={cost=e.cost,qty=e.quantity or 1,at=e.resolvedAt or e.at,sold=0}
   end
  end
 end
 table.sort(out,function(a,b) return (a.at or 0)>(b.at or 0) end)
 return out
end
-- Sales of the hovered item, newest first (per-unit price the buyer paid).
function M:SoldHistory(link)
 local name=nameOf(link);local out={}
 if not name then return out end
 for _,f in ipairs(self:FlipBook()) do
  if (f.sold or 0)>0 and type(f.name)=='string' and f.name:lower()==name:lower() then
   out[#out+1]={unit=math.floor((f.gross or 0)/f.sold+0.5),net=self:FlipNumbers(f).net,qty=f.sold,at=f.soldAt or f.at}
  end
 end
 table.sort(out,function(a,b) return (a.at or 0)>(b.at or 0) end)
 return out
end
local function charName(id) return type(id)=='string' and (id:match('^([^%-]+)') or id) or nil end
local function when(t) return t and date and (date('%m/%d %I:%M%p',t):gsub(' 0',' '):lower()) or '' end
-- Item tooltips: "Last Bought" / "Last Sold" always (like the per-item lines
-- other flippers use); hold Ctrl for dates, who bought it and averages.
function M:AppendBoughtTooltip(tip,link)
 if not self.db or not tip or not link then return end
 local hist,sold=self:BoughtHistory(link),self:SoldHistory(link)
 if #hist==0 and #sold==0 then return end
 local last=hist[1];local ls=sold[1]
 if last then tip:AddDoubleLine('Last Bought',self:Coins(math.floor(last.cost/math.max(1,last.qty))),.78,.63,1,1,1,1) end
 if ls then tip:AddDoubleLine('Last Sold',self:Coins(ls.unit),.78,.63,1,1,1,1) end
 if not (IsControlKeyDown and IsControlKeyDown()) then
  tip:AddLine('|cff8f8f8fHold Ctrl: when, who and averages|r');return
 end
 if last then
  local who=charName(last.char)
  tip:AddDoubleLine('  bought',when(last.at)..(who and (' by '..who) or '')..(last.qty>1 and (' (x'..last.qty..')') or ''),.7,.7,.7,.7,.7,.7)
 end
 if ls then tip:AddDoubleLine('  sold',when(ls.at)..', '..self:Coins(ls.net)..' after cut',.7,.7,.7,.7,.7,.7) end
 if #hist>1 then
  local total,qty=0,0;for _,h in ipairs(hist) do total=total+h.cost;qty=qty+h.qty end
  tip:AddDoubleLine('Bought '..#hist..' times','avg '..self:Coins(math.floor(total/qty)),.78,.63,1,.7,.7,.7)
 end
 if #sold>1 then
  local total,qty=0,0;for _,h in ipairs(sold) do total=total+h.unit*h.qty;qty=qty+h.qty end
  tip:AddDoubleLine('Sold '..#sold..' times','avg '..self:Coins(math.floor(total/qty)),.78,.63,1,.7,.7,.7)
 end
end
-- Oldest buy of this item you haven't sold yet (nil if none).
function M:HeldFlip(name,link,key)
 return openFlips(self,nameOf(link,name),key)[1]
end
-- Lowest post price that still gets back what you paid after the AH cut.
function M:PaidFloor(row)
 if type(row)~='table' or self.db.settings.sellNeverBelowPaid==false then return nil end
 local f=self:HeldFlip(row.name,row.itemLink,row.marketKey);if not f or not f.cost then return nil end
 local cut=tonumber(self.db.settings.ahCut) or 0.05;if not self:Finite(cut,0,0.3) then cut=0.05 end
 local unit=f.cost/math.max(1,f.qty or 1)
 if unit<=0 then return nil end
 return math.ceil(unit/(1-cut))
end
M:RegisterHandler('MODIFIER_STATE_CHANGED',function(self,_,key)
 if type(key)=='string' and not key:find('CTRL') then return end
 local tip=GameTooltip;if not (tip and tip.IsShown and tip:IsShown() and tip.GetItem and tip.GetOwner) then return end
 local _,link=tip:GetItem();if not link then return end
 local owner=tip:GetOwner();local enter=owner and owner.GetScript and owner:GetScript('OnEnter')
 if enter then pcall(enter,owner) end
end)

-- Selling screen: "You paid 9s 99c (11/12)" for the selected bag item.
function M:SellPaidText(row)
 if type(row)~='table' then return '' end
 local link=row.itemLink or (row.name and ('['..row.name..']'))
 local hist=link and self:BoughtHistory(link) or {}
 local last=hist[1];if not last then return '' end
 local each=math.floor(last.cost/math.max(1,last.qty))
 local text='|cffc8a0ffYou paid|r '..self:Coins(each)..' ('..(date and date('%m/%d',last.at or time()) or '')..')'
 if #hist>1 then local t,q=0,0;for _,h in ipairs(hist) do t=t+h.cost;q=q+h.qty end;text=text..'  avg '..self:Coins(math.floor(t/q)) end
 return text
end

-- Window --------------------------------------------------------------------
local function label(parent,text,x,y,w,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlight');f:SetPoint('TOPLEFT',x,y)
 if w then f:SetWidth(w) end;f:SetJustifyH('LEFT');f:SetText(text or '');if f.SetWordWrap then f:SetWordWrap(false) end;return f
end
local function button(parent,text,x,y,w,fn)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,22);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local DIM='|cff8f8f8f'
local function money(self,v) return v and self:Coins(v) or DIM..'--|r' end
local function profitText(self,v)
 if not v then return DIM..'--|r' end
 return (v>=0 and '|cff40ff40' or '|cffff6060-')..self:Coins(math.abs(v))..'|r'
end
local function day(t) return t and date and date('%m/%d',t) or DIM..'--|r' end
local function pct(v) if not v then return DIM..'--|r' end;return (v>=0 and '|cff40ff40' or '|cffff6060')..math.floor(v*100+0.5)..'%|r' end
local function days(v) if not v then return DIM..'--|r' end;return v<1 and ('%.0fh'):format(v*24) or ('%.1fd'):format(v) end
-- View definitions: columns {header, x, width, cell(self,row), sort(row)}.
local VIEWS={
 items={
  {'Item',8,214,function(_,f) return (f.qty or 1)>1 and (f.name..' x'..f.qty) or f.name end,function(f) return tostring(f.name):lower() end},
  {'Paid',226,78,function(s,f) return money(s,f.cost) end,function(f) return f.cost or -1 end},
  {'Bought',308,52,function(_,f) return day(f.cost and f.at) end,function(f) return f.at or 0 end},
  {'Listed at',364,78,function(s,f) return (s:FlipNumbers(f).open>0 and f.listPrice) and s:Coins(f.listPrice) or DIM..'--|r' end,function(f) return f.listPrice or -1 end},
  {'Sold for',446,78,function(s,f) return (f.sold or 0)>0 and s:Coins(s:FlipNumbers(f).net) or DIM..'--|r' end,function(f) return (f.sold or 0)>0 and ((f.gross or 0)-(f.fee or 0)) or -1 end},
  {'Sold',528,52,function(_,f) return (f.sold or 0)>0 and day(f.soldAt) or DIM..'--|r' end,function(f) return f.soldAt or 0 end},
  {'Days',584,44,function(s,f) return days(s:FlipNumbers(f).days) end,function(f) return M:FlipNumbers(f).days or 1e9 end},
  {'Profit',632,84,function(s,f) return profitText(s,s:FlipNumbers(f).profit) end,function(f) return M:FlipNumbers(f).profit or -1e15 end},
  {'Status',720,200,function(s,f) return s:FlipNumbers(f).status end,function(f) return M:FlipNumbers(f).status end}},
 groups={
  {'Name',8,220,function(_,g) return g.name end,function(g) return tostring(g.name):lower() end},
  {'Bought',232,52,function(_,g) return tostring(g.bought) end,function(g) return g.bought end},
  {'Sold',288,44,function(_,g) return tostring(g.sold) end,function(g) return g.sold end},
  {'Avg paid',336,82,function(s,g) return money(s,g.avgPaid) end,function(g) return g.avgPaid or -1 end},
  {'Avg sold',422,82,function(s,g) return money(s,g.avgSold) end,function(g) return g.avgSold or -1 end},
  {'Profit',508,88,function(s,g) return g.sold>0 and profitText(s,g.profit) or DIM..'--|r' end,function(g) return g.sold>0 and g.profit or -1e15 end},
  {'ROI',600,56,function(_,g) return pct(g.roi) end,function(g) return g.roi or -1e9 end},
  {'Days',660,50,function(_,g) return days(g.avgDays) end,function(g) return g.avgDays or 1e9 end},
  {'Holding',714,60,function(_,g) return tostring(g.holding) end,function(g) return g.holding end},
  {'Expired',778,60,function(_,g) return g.expired>0 and ('|cffff9060'..g.expired..'|r') or '0' end,function(g) return g.expired end}},
}
local MAXCOLS=10
-- Builds the ledger into a frame: the "Flip Ledger" AH tab (embedded, inside
-- the Market window) or a floating window (/vmm flips away from the AH).
local function buildLedger(self,f,embedded)
 do
  if not embedded then
   label(f,'|cffc8a0ffFLIP LEDGER|r',16,-14,200,'GameFontNormalLarge')
   button(f,'Close',852,-11,74,function() f:Hide() end)
  end
  button(f,'Export CSV',762,-11,86,function()
   if not self.ShowTransferWindow then return end
   self:ShowTransferWindow()
   if self.transferEdit then self.transferEdit:SetText(self:FlipLedgerCSV());self.transferEdit:SetFocus();self.transferEdit:HighlightText() end
   if self.transferStatus then self.transferStatus:SetText('Flip Ledger as CSV (copper). Ctrl+C to copy.') end
  end)
  -- View: every buy, or summaries.
  f.views={}
  for i,v in ipairs({{'items','Every buy'},{'byitem','By item'},{'bysuffix','By suffix'}}) do
   f.views[i]=button(f,v[2],200+(i-1)*94,-11,90,function() self.flipView=v[1];self.flipScroll=0;self.flipSort=nil;self:RenderFlipLedger() end)
   f.views[i].key=v[1]
  end
  -- Status filter (Every buy view) and time period (all views).
  f.filters={}
  for i,v in ipairs({{'all','All'},{'holding','Holding'},{'sold','Sold'}}) do
   f.filters[i]=button(f,v[2],16+(i-1)*76,-40,72,function() self.flipFilter=v[1];self.flipScroll=0;self:RenderFlipLedger() end)
   f.filters[i].key=v[1]
  end
  f.periods={}
  for i,v in ipairs({{'all','All time'},{'week','7 days'},{'today','Today'}}) do
   f.periods[i]=button(f,v[2],260+(i-1)*84,-40,80,function() self.flipPeriod=v[1];self.flipScroll=0;self:RenderFlipLedger() end)
   f.periods[i].key=v[1]
  end
  f.headers={}
  for i=1,MAXCOLS do
   local h=CreateFrame('Button',nil,f);h:SetSize(80,18);h.index=i
   h.text=label(h,'',0,-2,nil,'GameFontNormal')
   h:SetScript('OnClick',function(b)
    local s=self.flipSort
    if s and s.col==b.index then s.dir=-s.dir else self.flipSort={col=b.index,dir=b.index==1 and 1 or -1} end
    self.flipScroll=0;self:RenderFlipLedger()
   end)
   f.headers[i]=h
  end
  f.rows={}
  for i=1,ROWS do
   local r=CreateFrame('Button',nil,f);r:SetPoint('TOPLEFT',8,-92-(i-1)*ROW_H);r:SetSize(924,ROW_H-1)
   if r.RegisterForClicks then r:RegisterForClicks('LeftButtonUp','RightButtonUp') end
   r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
   r.c={};for j=1,MAXCOLS do r.c[j]=label(r,'',0,-4,80) end
   r:SetScript('OnClick',function(b,mouse)
    if mouse~='RightButton' or not b.flip then return end
    local id,name=b.flip.id,b.flip.name
    if self.AskShopConfirm then self:AskShopConfirm('Remove "'..tostring(name)..'" from the Flip Ledger?',function() self:RemoveFlip(id) end) end
   end)
   f.rows[i]=r
  end
  f:EnableMouseWheel(true)
  f:SetScript('OnMouseWheel',function(_,d) self.flipScroll=math.max(0,(self.flipScroll or 0)-(d>0 and 3 or -3));self:RenderFlipLedger() end)
  f.empty=label(f,'',14,-260,912);f.empty:SetJustifyH('CENTER')
  f.totals=label(f,'',14,-480,912,'GameFontNormal')
  f.totals2=label(f,'',14,-502,912,'GameFontHighlight')
  f.hint=label(f,DIM..'Buys from Market and the normal AH are recorded. Sales and expired auctions are read when you open your mailbox. Click a header to sort; right-click a buy to remove it.|r',14,-530,912,'GameFontHighlightSmall')
 end
end
-- Floating window. While the AH is open with Market's tabs, the tab is used instead.
function M:ShowFlipLedger()
 if self.auctionTabs and self.ahOpen then
  for _,t in ipairs(self.auctionTabs) do
   if t.key=='flipledger' and t.button and t.button:GetScript('OnClick') then t.button:GetScript('OnClick')(t.button);return end
  end
 end
 local f=self.flipLedger
 if not f then
  f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');self.flipLedger=f
  f:SetSize(940,560);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetMovable(true);f:EnableMouse(true)
  f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',function(w) w:StartMoving() end);f:SetScript('OnDragStop',function(w) w:StopMovingOrSizing() end)
  if f.SetBackdrop then
   f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=14})
   f:SetBackdropColor(0.035,0.026,0.065,0.98);f:SetBackdropBorderColor(0.48,0.25,0.75,1)
  end
  buildLedger(self,f,false)
 end
 f:Show();self:RenderFlipLedger()
end
-- The AH tab: lives in the Market window like Shopping/Selling/Listings.
function M:InitializeFlipScreen(parent)
 if self.flipScreen then return end
 local f=CreateFrame('Frame',nil,parent);f:SetPoint('TOPLEFT',18,-108);f:SetSize(1004,554);f:Hide()
 self.flipScreen=f
 buildLedger(self,f,true)
end
function M:RenderFlipScreen()
 local f=self.flipScreen;if not f then return end
 f:Show();self:RenderFlipFrame(f)
end
function M:RenderFlipLedger()
 if self.flipScreen and self.flipScreen:IsShown() then self:RenderFlipFrame(self.flipScreen) end
 if self.flipLedger and self.flipLedger:IsShown() then self:RenderFlipFrame(self.flipLedger) end
end
function M:RenderFlipFrame(f)
 if not f or not f:IsShown() then return end
 local view=self.flipView or 'items';local filter=self.flipFilter or 'all';local period=self.flipPeriod or 'all'
 for _,b in ipairs(f.views) do b:SetEnabled(b.key~=view) end
 for _,b in ipairs(f.filters) do b:SetEnabled(b.key~=filter);b:SetShown(view=='items') end
 for _,b in ipairs(f.periods) do b:SetEnabled(b.key~=period) end
 local cols=view=='items' and VIEWS.items or VIEWS.groups
 local rows=view=='items' and self:FlipRows(filter,period) or self:FlipGroups(view=='bysuffix' and 'suffix' or 'item',period)
 local sort=self.flipSort
 if sort and cols[sort.col] then
  local key=cols[sort.col][5]
  table.sort(rows,function(a,b)
   local av,bv=key(a),key(b)
   if av~=bv then if sort.dir>0 then return av<bv else return av>bv end end
   return tostring(a.name)<tostring(b.name)
  end)
 elseif view~='items' then
  table.sort(rows,function(a,b) if a.profit~=b.profit then return a.profit>b.profit end return a.name<b.name end)
 end
 for i,h in ipairs(f.headers) do
  local c=cols[i];h:SetShown(c~=nil)
  if c then
   h:ClearAllPoints();h:SetPoint('TOPLEFT',8+c[2],-70);h:SetWidth(c[3])
   local arrow=(sort and sort.col==i) and (sort.dir>0 and ' ^' or ' v') or ''
   h.text:SetText(c[1]..arrow)
  end
 end
 local off=math.max(0,math.min(self.flipScroll or 0,#rows-ROWS));self.flipScroll=off
 for i,r in ipairs(f.rows) do
  local row=rows[off+i];r.flip=view=='items' and row or nil;r:SetShown(row~=nil)
  for j,cell in ipairs(r.c) do
   local c=cols[j];cell:SetShown(c~=nil and row~=nil)
   if c and row then cell:ClearAllPoints();cell:SetPoint('TOPLEFT',c[2],-4);cell:SetWidth(c[3]-4);cell:SetText(c[4](self,row)) end
  end
 end
 local empty=''
 if #rows==0 then
  empty=#self:FlipBook()==0 and 'Nothing here yet. Items you buy show up here; sales appear after you open your mailbox.'
   or 'Nothing in this view for the chosen time period.'
 end
 f.empty:SetText(empty)
 local t=self:FlipTotals(period)
 f.totals:SetText(('Spent %s   |   Sold for %s   |   Profit on sold %s'):format(self:Coins(t.spent),self:Coins(t.net),profitText(self,t.profit))
  ..(t.lost>0 and ('   |   Deposits lost '..self:Coins(t.lost)) or ''))
 f.totals2:SetText(('Holding %d (paid %s)%s'):format(t.holding,self:Coins(t.holdingCost),
  t.listedValue>0 and ('   |   Listed for %s if they all sell'):format(self:Coins(math.floor(t.listedValue*(1-(self.db.settings.ahCut or 0.05))))) or ''))
end
