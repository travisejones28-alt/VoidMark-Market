local _,M=...
-- Flip Ledger (1.15.0): what you paid for each item you bought, and what it
-- sold for. Purchases come from confirmed buys; sales from AH sale invoices
-- read at the mailbox, matched to the oldest unsold purchase of the same item.
-- Sales with no matching purchase are still listed (cost unknown).
local MAX_ROWS=600
local ROWS,ROW_H=16,22

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
-- Called when a purchase is confirmed (Ledger ResolvePurchase).
function M:RecordFlipBuy(p)
 if self.persistenceBlocked or type(p)~='table' or not self:Finite(p.cost,0,1e14) then return end
 local qty=tonumber(p.quantity) or 1;if qty<1 then return end
 local book=self:FlipBook()
 self.db.flipSequence=(tonumber(self.db.flipSequence) or 0)+1
 book[#book+1]={id=self.db.flipSequence,name=nameOf(p.itemLink,p.name) or ('Item '..tostring(p.itemID)),key=p.marketKey,
  itemID=p.itemID,qty=qty,cost=math.floor(p.cost),at=time(),char=self.characterID,sold=0,gross=0,fee=0}
 trimBook(self);self:RefreshUI()
end
local function sameItem(a,b)
 a,b=tostring(a or ''):lower(),tostring(b or ''):lower()
 if a=='' or b=='' then return false end
 return a==b or a:sub(1,#b)==b or b:sub(1,#a)==a
end
-- Called for each new AH sale invoice (Ledger ObserveMail). gross/fee in copper.
function M:RecordFlipSale(name,qty,gross,fee)
 if self.persistenceBlocked or type(name)~='string' or name=='' or not self:Finite(gross,0,1e14) then return end
 qty=tonumber(qty) or 1;if qty<1 then qty=1 end
 fee=self:Finite(fee,0,gross) and fee or 0
 local book=self:FlipBook();local left=qty
 -- Oldest unsold purchase first; exact names before partial ones.
 for pass=1,2 do
  for _,f in ipairs(book) do
   if left<=0 then break end
   local open=(f.qty or 1)-(f.sold or 0)
   local match=pass==1 and tostring(f.name):lower()==name:lower() or pass==2 and sameItem(f.name,name)
   if f.cost~=nil and open>0 and match then
    local take=math.min(open,left)
    f.sold=(f.sold or 0)+take;f.gross=(f.gross or 0)+gross*take/qty;f.fee=(f.fee or 0)+fee*take/qty
    f.soldAt=time();left=left-take
   end
  end
 end
 if left>0 then
  self.db.flipSequence=(tonumber(self.db.flipSequence) or 0)+1
  book[#book+1]={id=self.db.flipSequence,name=name,qty=left,cost=nil,at=time(),soldAt=time(),char=self.characterID,
   sold=left,gross=gross*left/qty,fee=fee*left/qty}
 end
 trimBook(self);self:RefreshUI()
end
-- Profit of the sold part (net after AH cut minus what that part cost).
function M:FlipNumbers(f)
 local qty=f.qty or 1;local sold=f.sold or 0
 local net=(f.gross or 0)-(f.fee or 0)
 local soldCost=f.cost and f.cost*sold/qty or nil
 local profit=(sold>0 and soldCost) and math.floor(net-soldCost+0.5) or nil
 local status=f.cost==nil and 'Sold (no buy record)' or sold>=qty and 'Sold' or sold>0 and ('Sold '..sold..'/'..qty) or 'Holding'
 return {net=math.floor(net+0.5),profit=profit,status=status,open=f.cost and qty-sold or 0}
end
function M:FlipTotals()
 local t={spent=0,net=0,profit=0,holding=0,holdingCost=0,sold=0}
 for _,f in ipairs(self:FlipBook()) do
  local n=self:FlipNumbers(f)
  if f.cost then t.spent=t.spent+f.cost end
  t.net=t.net+n.net
  if n.profit then t.profit=t.profit+n.profit;t.sold=t.sold+(f.sold or 0) end
  if n.open>0 then t.holding=t.holding+n.open;t.holdingCost=t.holdingCost+f.cost*n.open/(f.qty or 1) end
 end
 t.holdingCost=math.floor(t.holdingCost+0.5)
 return t
end
function M:FlipRows(filter)
 local out={}
 for _,f in ipairs(self:FlipBook()) do
  local n=self:FlipNumbers(f)
  if filter=='holding' and n.open>0 or filter=='sold' and (f.sold or 0)>0 or filter~='holding' and filter~='sold' then out[#out+1]=f end
 end
 table.sort(out,function(a,b) return (a.soldAt or a.at or 0)>(b.soldAt or b.at or 0) end)
 return out
end
function M:RemoveFlip(id)
 local book=self:FlipBook()
 for i=#book,1,-1 do if book[i].id==id then table.remove(book,i) end end
 self:RefreshUI()
end

-- Ctrl + hover: what you last paid -------------------------------------------
-- Your buys of the hovered item (same name, or same item + suffix), newest first.
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
  if f.cost and same(f.name,f.key) then out[#out+1]={cost=f.cost,qty=f.qty or 1,at=f.at,sold=f.sold or 0,net=self:FlipNumbers(f).net,soldAt=f.soldAt} end
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
function M:AppendBoughtTooltip(tip,link)
 if not self.db or not tip or not link then return end
 local hist=self:BoughtHistory(link);if #hist==0 then return end
 if not (IsControlKeyDown and IsControlKeyDown()) then
  tip:AddLine('|cff8f8f8fHold Ctrl: what you paid|r');return
 end
 local last=hist[1]
 local when=date and date('%m/%d %I:%M%p',last.at or time()):gsub(' 0',' '):lower() or ''
 local each=last.qty>1 and (' ('..self:Coins(math.floor(last.cost/last.qty))..' each)') or ''
 tip:AddDoubleLine('Last bought',self:Coins(last.cost)..each,.78,.63,1,1,1,1)
 tip:AddDoubleLine(' ',when..(last.sold>0 and (', sold for '..self:Coins(last.net)) or ''),1,1,1,.7,.7,.7)
 if #hist>1 then
  local total,qty=0,0;for _,h in ipairs(hist) do total=total+h.cost;qty=qty+h.qty end
  tip:AddDoubleLine('Bought '..#hist..' times','avg '..self:Coins(math.floor(total/qty)),.78,.63,1,.7,.7,.7)
 end
end
-- Redraw the item tooltip when Ctrl goes down or up.
M:RegisterHandler('MODIFIER_STATE_CHANGED',function(self,_,key)
 if type(key)=='string' and not key:find('CTRL') then return end
 local tip=GameTooltip;if not (tip and tip.IsShown and tip:IsShown() and tip.GetItem and tip.GetOwner) then return end
 local _,link=tip:GetItem();if not link then return end
 local owner=tip:GetOwner();local enter=owner and owner.GetScript and owner:GetScript('OnEnter')
 if enter then pcall(enter,owner) end
end)

-- Window --------------------------------------------------------------------
local function label(parent,text,x,y,w,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlight');f:SetPoint('TOPLEFT',x,y)
 if w then f:SetWidth(w) end;f:SetJustifyH('LEFT');f:SetText(text or '');return f
end
local function button(parent,text,x,y,w,fn)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,22);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local COLS={{'Item',14,250},{'Paid',268,96},{'Sold for',368,96},{'Profit',468,96},{'Date',568,80},{'Status',652,140}}
function M:ShowFlipLedger()
 local f=self.flipLedger
 if not f then
  f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');self.flipLedger=f
  f:SetSize(800,500);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetMovable(true);f:EnableMouse(true)
  f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',function(w) w:StartMoving() end);f:SetScript('OnDragStop',function(w) w:StopMovingOrSizing() end)
  if f.SetBackdrop then
   f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=14})
   f:SetBackdropColor(0.035,0.026,0.065,0.98);f:SetBackdropBorderColor(0.48,0.25,0.75,1)
  end
  label(f,'|cffc8a0ffFLIP LEDGER|r',16,-14,300,'GameFontNormalLarge')
  button(f,'Close',712,-11,74,function() f:Hide() end)
  f.filters={}
  for i,v in ipairs({{'all','All'},{'holding','Holding'},{'sold','Sold'}}) do
   f.filters[i]=button(f,v[2],330+(i-1)*84,-11,80,function() self.flipFilter=v[1];self.flipScroll=0;self:RenderFlipLedger() end)
   f.filters[i].key=v[1]
  end
  for _,c in ipairs(COLS) do label(f,c[1],c[2],-48,c[3],'GameFontNormal') end
  f.rows={}
  for i=1,ROWS do
   local r=CreateFrame('Button',nil,f);r:SetPoint('TOPLEFT',8,-68-(i-1)*ROW_H);r:SetSize(784,ROW_H-1)
   if r.RegisterForClicks then r:RegisterForClicks('LeftButtonUp','RightButtonUp') end
   r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
   r.c={};for j,c in ipairs(COLS) do r.c[j]=label(r,'',c[2]-8,-4,c[3]) end
   r:SetScript('OnClick',function(b,mouse)
    if mouse~='RightButton' or not b.flip then return end
    local id,name=b.flip.id,b.flip.name
    if self.AskShopConfirm then self:AskShopConfirm('Remove "'..tostring(name)..'" from the Flip Ledger?',function() self:RemoveFlip(id) end) end
   end)
   f.rows[i]=r
  end
  f:EnableMouseWheel(true)
  f:SetScript('OnMouseWheel',function(_,d) self.flipScroll=math.max(0,(self.flipScroll or 0)-(d>0 and 3 or -3));self:RenderFlipLedger() end)
  f.empty=label(f,'',14,-200,772);f.empty:SetJustifyH('CENTER')
  f.totals=label(f,'',14,-430,772,'GameFontNormal')
  f.hint=label(f,'|cff8f8f8fSales are read from AH sale mail when you open your mailbox. Paid = what you paid; Sold for = after the AH cut. Right-click a row to remove it.|r',14,-456,772,'GameFontHighlightSmall')
 end
 f:Show();self:RenderFlipLedger()
end
function M:RenderFlipLedger()
 local f=self.flipLedger;if not f or not f:IsShown() then return end
 local filter=self.flipFilter or 'all'
 for _,b in ipairs(f.filters) do b:SetEnabled(b.key~=filter) end
 local rows=self:FlipRows(filter)
 local off=math.max(0,math.min(self.flipScroll or 0,#rows-ROWS));self.flipScroll=off
 for i,r in ipairs(f.rows) do
  local fl=rows[off+i];r.flip=fl;r:SetShown(fl~=nil)
  if fl then
   local n=self:FlipNumbers(fl)
   r.c[1]:SetText((fl.qty or 1)>1 and (fl.name..' x'..fl.qty) or fl.name)
   r.c[2]:SetText(fl.cost and self:Coins(fl.cost) or '|cff8f8f8f--|r')
   r.c[3]:SetText((fl.sold or 0)>0 and self:Coins(n.net) or '|cff8f8f8f--|r')
   r.c[4]:SetText(n.profit and ((n.profit>=0 and '|cff40ff40' or '|cffff6060-')..self:Coins(math.abs(n.profit))..'|r') or '|cff8f8f8f--|r')
   r.c[5]:SetText(date and date('%m/%d',fl.soldAt or fl.at) or '')
   r.c[6]:SetText(n.status)
  end
 end
 f.empty:SetText(#rows==0 and 'Nothing here yet. Items you buy show up here; sales appear after you open your mailbox.' or '')
 local t=self:FlipTotals()
 f.totals:SetText(('Spent %s  |  Sold for %s  |  Profit on sold %s%s|r  |  Holding %d (%s)'):format(
  self:Coins(t.spent),self:Coins(t.net),t.profit>=0 and '|cff40ff40' or '|cffff6060-',self:Coins(math.abs(t.profit)),t.holding,self:Coins(t.holdingCost)))
end
