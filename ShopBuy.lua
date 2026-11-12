local _,M=...
-- Auctionator-style buy view inside Shopping (behavior reference: Auctionator 342,
-- Source_ModernAH/Tabs/Buying; independent implementation, VoidMark styling).
-- Click a result: Back / item / refresh on top, Quantity + Unit + Total + Buy Now
-- on the left, live price tiers on the right. Commodities: type a quantity or
-- click a tier (buys every tier up to it). Items: click a listing, Buy Now.
-- After every purchase the listing refreshes and the quantity is kept, so Buy
-- Now can be pressed again (chain buying). Every purchase goes through the
-- normal VoidMark execution path: risk limits, ledger, pending reservations.
local ROWS=14
local WIDE=0.5 -- Auctionator warns when the dearest unit is 50%+ above the cheapest
local busyStates={validating=true,quoting=true,quoted=true,pending=true}

local function label(parent,text,x,y,w,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontNormalSmall');f:SetPoint('TOPLEFT',x,y)
 if w then f:SetWidth(w) end;f:SetJustifyH('LEFT');f:SetText(text or '');return f
end
local function button(parent,text,x,y,w,fn,h)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,h or 24);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local function red(s) return '|cffff5555'..s..'|r' end
local function gold(s) return '|cffffd100'..s..'|r' end

-- State --------------------------------------------------------------------
function M:ShopBuyOpen(row)
 local key,id,s,l,p=self:ParseKey(row and row.marketKey)
 if not key then self:Print('Select an item first');return end
 local m=self.db.market[key] or {marketKey=key,itemID=id,itemSuffix=s,itemLevel=l,battlePetSpeciesID=p,
  name=row.name or ('Item '..id),latest={},observations=0}
 local old=self.shopBuy
 if old and old.key==key then self:ShopBuyRefresh();return end
 self:ShopBuyClose()
 self.selectedRow=row
 self.shopBuy={key=key,market=m,name=row.name or m.name or ('Item '..id),quantity=1,pick=1,offset=0,token=0}
 self:ShopBuyRefresh()
end
function M:ShopBuyClose()
 local b=self.shopBuy;if not b then return end
 local x=self.execution
 if x and x.shop==b and (x.state=='quoting' or x.state=='quoted') then self:InvalidateQuote('Buy view closed') end
 b.token=b.token+1;self.shopBuy=nil;self:RefreshUI()
end
function M:ShopBuyRefresh()
 local b=self.shopBuy;if not b then return end
 if not self.ahOpen then b.searching=false;b.status='Open the Auction House to see live listings.';self:RefreshUI();return end
 b.token=b.token+1;local token=b.token
 b.searching=true;b.status=nil
 self:Search(b.market,90,function(result)
  if self.shopBuy~=b or b.token~=token then return end
  b.searching=false;b.commodity=result.commodity;b.rows=result.rows;b.at=GetTime();b.max=0
  for _,r in ipairs(b.rows) do b.max=b.max+r.quantity end
  if b.commodity then
   if b.max>0 then b.quantity=math.max(1,math.min(b.quantity or 1,b.max)) end
  else b.pick=1 end
  b.offset=0
  b.status=#b.rows==0 and 'None available to buy right now.' or nil
  self:RefreshUI()
 end,function(err)
  if self.shopBuy~=b or b.token~=token then return end
  b.searching=false;b.status='Search failed: '..tostring(err)..'. Press Refresh.';self:RefreshUI()
 end,function() return self.shopBuy==b and b.token==token end)
 self:RefreshUI()
end
function M:ShopBuySetQuantity(n)
 local b=self.shopBuy;if not b or not b.commodity then return end
 n=math.floor(tonumber(n) or 0);if n<0 then n=0 end
 if b.max then n=math.min(n,b.max) end
 b.quantity=n;self:RefreshUI()
end
-- Clicking a commodity tier buys every tier up to and including it.
function M:ShopBuyPickRow(index)
 local b=self.shopBuy;if not b or not b.rows or not b.rows[index] then return end
 if b.commodity then
  local q=0;for i=1,index do q=q+b.rows[i].quantity end
  b.quantity=q
 else b.pick=index end
 self:RefreshUI()
end

-- Prices --------------------------------------------------------------------
function M:ShopBuyPrices(b)
 b=b or self.shopBuy;if not b or not b.rows then return end
 if not b.commodity then
  local r=b.rows[b.pick or 1];if not r then return end
  return r.unit,r.total,r.unit,r.unit,r.quantity
 end
 local q=b.quantity or 0;if q<1 then return end
 local left,total,minU,maxU=q,0
 for _,r in ipairs(b.rows) do
  if left<=0 then break end
  local take=math.min(left,r.quantity);total=total+take*r.unit;left=left-take
  minU=minU or r.unit;maxU=r.unit
 end
 if left>0 then return end
 return math.ceil(total/q),total,minU,maxU,q
end
local function wide(minU,maxU) return minU and maxU and minU>0 and (maxU-minU)/minU>=WIDE end
local limitText={
 ['Quantity limit']=function(s) return 'Over your quantity limit ('..s.maxQuantity..'). Change it in Settings.' end,
 ['Transaction spend limit']=function(s,self) return 'Over your per-purchase limit ('..self:Money(s.maxTransaction)..'). Change it in Settings.' end,
 ['Item exposure limit']=function() return 'Over your spend limit for this item. Change it in Settings.' end,
 ['Portfolio exposure limit']=function() return 'Over your total spend limit. Change it in Settings.' end,
 ['Liquid gold reserve / pending reservations']=function() return 'Not enough gold (after your reserve and unresolved purchases).' end,
}
-- Returns whether Buy Now can be pressed, and the lines to show under it.
function M:ShopBuyCheck(b)
 b=b or self.shopBuy;local lines={}
 if not b then return false,lines end
 local x=self.execution
 local mine=x and x.shop==b
 if mine and busyStates[x.state] then
  local msg={validating='Checking...',quoting='Checking the current price...',quoted='Confirm the purchase in the popup.',pending='Buying...'}
  lines[1]=gold(msg[x.state]);return false,lines
 end
 if b.done then lines[#lines+1]='|cff66ff66'..b.done..'|r' end
 if mine and (x.state=='invalid' or x.state=='failed' or x.state=='unknown' or x.state=='stale') and x.message then lines[#lines+1]=red(x.message) end
 if self.persistenceBlocked then lines[#lines+1]=red('Read-only: database is newer than this addon.');return false,lines end
 if not self.ahOpen then lines[#lines+1]='Open the Auction House.';return false,lines end
 if b.searching then lines[#lines+1]=gold('Searching the Auction House...');return false,lines end
 if b.status then lines[#lines+1]=b.status;return false,lines end
 if self:HasUnresolvedPurchase() then
  local p=self:OldestUnresolvedPurchase()
  lines[#lines+1]=red('Did your last purchase'..(p and p.name and (' ('..p.name..')') or '')..' go through? Check chat or your mailbox, then click below.')
  return false,lines
 end
 local unit,total,minU,maxU,q=self:ShopBuyPrices(b)
 if not total then
  if b.commodity and (b.quantity or 0)>0 then lines[#lines+1]=red('Only '..(b.max or 0)..' available.')
  else lines[#lines+1]=b.commodity and 'Enter a quantity or click a price.' or 'Click a listing.' end
  return false,lines
 end
 local ok=true
 local money=GetMoney and GetMoney()
 if not (self:Finite(money,0,1e14) and total<=money) then lines[#lines+1]=red('Not enough gold.');ok=false end
 local pass,why=self:CheckRisk(b.market,self:Economics(b.market,total,q,'shopping'))
 if not pass then
  local s=self.db.settings
  for _,w in ipairs(why) do
   local f=limitText[w];local text=f and f(s,self) or w
   if not (text:find('Not enough gold',1,true) and not ok) then lines[#lines+1]=red(text) end
  end
  ok=false
 end
 local guard=(self.db.quoteGuardUntil or 0)-time()
 if b.commodity and guard>0 then lines[#lines+1]=gold('Wait '..guard..'s before the next commodity buy.');ok=false end
 if b.commodity and wide(minU,maxU) then
  lines[#lines+1]=gold('CAREFUL: the price varies a lot ('..self:Coins(minU)..' - '..self:Coins(maxU)..').')
 end
 return ok,lines
end

-- Buying --------------------------------------------------------------------
local function popup(self,text,accept,cancel,timeout)
 if not StaticPopupDialogs or not StaticPopup_Show then self:Print('Confirmation dialog unavailable');return false end
 StaticPopupDialogs.VOIDMARKMARKET_SHOPBUY=StaticPopupDialogs.VOIDMARKMARKET_SHOPBUY or {
  text='%s',button1=ACCEPT or 'Accept',button2=CANCEL or 'Cancel',whileDead=false,hideOnEscape=true,preferredIndex=3,
  OnAccept=function(_,data) if data and data.accept then data.accept() end end,
  OnCancel=function(_,data) if data and data.cancel then data.cancel() end end}
 StaticPopupDialogs.VOIDMARKMARKET_SHOPBUY.timeout=timeout or 0
 StaticPopup_Show('VOIDMARKMARKET_SHOPBUY',text,nil,{accept=accept,cancel=cancel})
 return true
end
local function hidePopup()
 if StaticPopup_Hide then pcall(StaticPopup_Hide,'VOIDMARKMARKET_SHOPBUY') end
end
function M:ShopBuyNow()
 local b=self.shopBuy;local ok,lines=self:ShopBuyCheck(b)
 if not ok then if lines[#lines] then self:Print((lines[#lines]:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r',''))) end;return end
 if not self:ThrottleReady() then self:Print('The Auction House is busy; try again in a moment');return end
 local unit,total,minU,maxU,q=self:ShopBuyPrices(b)
 if b.commodity then
  if wide(minU,maxU) then
   popup(self,red('CAREFUL')..'\n\nThe price varies a lot between listings.\n\nUnit price: '..self:Coins(minU)..' - '..self:Coins(maxU),
    function() if self.shopBuy==b then self:ShopBuyStart() end end)
   return
  end
  return self:ShopBuyStart()
 end
 local r=b.rows[b.pick or 1]
 popup(self,'Paying '..self:Coins(r.total)..' for '..(r.quantity>1 and (r.quantity..' x ') or '')..b.name..'?',
  function() if self.shopBuy==b and b.rows and b.rows[b.pick or 1]==r then self:ShopBuyStart() end end)
end
function M:ShopBuyStart()
 local b=self.shopBuy;if not b then return end
 local ok=self:ShopBuyCheck(b);if not ok then return end
 local unit,total,_,_,q=self:ShopBuyPrices(b)
 local live={quantity=q,cost=total,received=GetTime(),at=time()}
 if not b.commodity then live.auctionID=b.rows[b.pick or 1].auctionID end
 live.economics=self:Economics(b.market,total,q,'shopping')
 self.executionToken=(self.executionToken or 0)+1
 b.done=nil
 self.execution={state='ready',opportunity={marketKey=b.key,kind='shopping',shoppingMarket=b.market},market=b.market,
  token=self.executionToken,commodity=b.commodity,live=live,shop=b,quoteWindow=15,expectedUnit=unit,
  message='Buying '..q..' x '..b.name}
 self:ExecuteClicked()
 self:RefreshUI()
end
-- Called by Execution when the server quotes a commodity purchase.
function M:ShopBuyQuoted(x,unit,total,increased)
 local b=x.shop
 local text=(increased and (red('The price has increased!')..'\n\n') or '')..
  'Confirm purchase of '..x.live.quantity..' x '..b.name..' for '..self:Coins(total)..'?\n\n('..self:Coins(unit)..' each)'
 popup(self,text,function() if self.execution==x and x.state=='quoted' then
   if not self:ThrottleReady() then self:Print('The Auction House is busy; buy again');self:InvalidateQuote('Auction House busy; buy again');return end
   self:ConfirmClicked() end end,
  function() if self.execution==x and (x.state=='quoted' or x.state=='quoting') then self:InvalidateQuote('Purchase cancelled') end end,
  x.quoteWindow or 15)
end
local function afterPurchase(self,ok)
 local x=self.execution;local b=x and x.shop
 if not b or b~=self.shopBuy then return end
 hidePopup()
 if ok then b.done='Bought '..x.live.quantity..' x '..b.name..' for '..self:Money(x.live.cost) end
 self:ShopBuyRefresh() -- keep the quantity so Buy Now can be pressed again
end
M:RegisterHandler('COMMODITY_PURCHASE_SUCCEEDED',function(self) local x=self.execution;if x.shop and x.state=='complete' then afterPurchase(self,true) end end)
M:RegisterHandler('COMMODITY_PURCHASE_FAILED',function(self) local x=self.execution;if x.shop and (x.state=='failed' or x.state=='invalid') then afterPurchase(self,false) end end)
M:RegisterHandler('AUCTION_HOUSE_PURCHASE_COMPLETED',function(self) local x=self.execution;if x.shop and x.state=='complete' and not x.shopDone then x.shopDone=true;afterPurchase(self,true) end end)
M:RegisterHandler('AUCTION_HOUSE_SHOW_ERROR',function(self) local x=self.execution;if x.shop and x.shop==self.shopBuy then hidePopup();self:ShopBuyRefresh() end end)
M:RegisterHandler('AUCTION_HOUSE_CLOSED',function(self) hidePopup();local b=self.shopBuy;if b then b.token=b.token+1;b.rows=nil;b.searching=false;b.status=nil;self:RefreshUI() end end)
M:RegisterHandler('AUCTION_HOUSE_SHOW',function(self) if self.shopBuy then self:ShopBuyRefresh() end end)

-- View ----------------------------------------------------------------------
function M:InitializeShopBuyView(s)
 local v=self.panel(s,312,-56,692,498);v:Hide();s.buyView=v
 button(v,'Back',12,-10,90,function() self:ShopBuyClose() end)
 v.iconButton=CreateFrame('Button',nil,v);v.iconButton:SetPoint('TOPLEFT',14,-44);v.iconButton:SetSize(40,40)
 v.icon=v.iconButton:CreateTexture(nil,'ARTWORK');v.icon:SetAllPoints()
 v.iconButton:SetScript('OnEnter',function(f)
  local b=self.shopBuy;if not b or not GameTooltip then return end
  -- Below the icon, inside the buy view (ANCHOR_RIGHT grew upward over the search bar).
  GameTooltip:SetOwner(f,'ANCHOR_NONE');GameTooltip:ClearAllPoints();GameTooltip:SetPoint('TOPLEFT',f,'BOTTOMLEFT',0,-6)
  local row=b.rows and b.rows[b.pick or 1]
  local shown=self:SetVariantTooltip(GameTooltip,b.key or b.market.marketKey,b.market.itemID,(row and row.itemLink) or b.market.itemLink)
  if not shown then GameTooltip:SetText(b.name or '?') end
  GameTooltip:Show()
 end)
 v.iconButton:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
 v.name=label(v,'',64,-56,500,'GameFontNormalLarge')
 v.refresh=button(v,'Refresh',590,-50,90,function() self:ShopBuyRefresh() end)
 -- Details (left)
 v.qtyLabel=label(v,'Quantity',14,-112,80,'GameFontNormal')
 v.qty=CreateFrame('EditBox',nil,v,'InputBoxTemplate');v.qty:SetPoint('TOPLEFT',104,-106);v.qty:SetSize(90,22);v.qty:SetAutoFocus(false)
 if v.qty.SetNumeric then v.qty:SetNumeric(true) end
 v.qty:SetScript('OnEscapePressed',function(e) e:ClearFocus() end)
 v.qty:SetScript('OnEnterPressed',function(e) e:ClearFocus() end)
 v.qty:SetScript('OnTextChanged',function(e,user) if user then self:ShopBuySetQuantity(e:GetText()) end end)
 v.maxButton=button(v,'Max',200,-105,56,function() local b=self.shopBuy;if b and b.max then self:ShopBuySetQuantity(b.max) end end,22)
 v.itemHint=label(v,'Click a listing on the right,\nthen Buy Now.',14,-108,250,'GameFontHighlightSmall')
 label(v,'Unit price',14,-150,80,'GameFontNormal');v.unit=label(v,'',104,-150,170,'GameFontHighlight')
 label(v,'Total price',14,-182,80,'GameFontNormal');v.total=label(v,'',104,-182,170,'GameFontHighlight')
 v.buyNow=button(v,'Buy Now',14,-218,242,function() self:ShopBuyNow() end,28)
 v.status=label(v,'',14,-258,262,'GameFontHighlightSmall');v.status:SetJustifyV('TOP')
 -- Unknown purchase result: settle it here instead of the Ledger.
 v.gotIt=button(v,'I got it',14,-330,118,function() self:ShopSettleUnknown(true) end,24)
 v.didnt=button(v,"Didn't get it",138,-330,118,function() self:ShopSettleUnknown(false) end,24)
 v.gotIt:Hide();v.didnt:Hide()
 v.money=label(v,'',14,-470,262,'GameFontHighlightSmall')
 -- Listings (right)
 local list=self.panel(v,286,-96,398,394);v.list=list
 v.cols={label(list,'Buyout price',12,-10,140),label(list,'Each',150,-10,120),label(list,'Available',280,-10,100)}
 v.rows={}
 for i=1,ROWS do
  local r=CreateFrame('Button',nil,list);r:SetPoint('TOPLEFT',6,-28-(i-1)*25);r:SetSize(386,24)
  r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  r.sel=r:CreateTexture(nil,'BACKGROUND');r.sel:SetAllPoints();r.sel:SetColorTexture(.32,.15,.5,.55)
  r.c={label(r,'',6,-6,138,'GameFontHighlight'),label(r,'',144,-6,124,'GameFontHighlight'),label(r,'',274,-6,100,'GameFontHighlight')}
  r:SetScript('OnClick',function(f) if f.index then self:ShopBuyPickRow(f.index) end end)
  r:SetScript('OnDoubleClick',function(f) if f.index then self:ShopBuyPickRow(f.index);self:ShopBuyNow() end end)
  v.rows[i]=r
 end
 list:EnableMouseWheel(true)
 list:SetScript('OnMouseWheel',function(_,d)
  local b=self.shopBuy;if not b or not b.rows then return end
  b.offset=math.max(0,math.min(math.max(0,#b.rows-ROWS),(b.offset or 0)-(d>0 and 3 or -3)));self:RefreshUI()
 end)
 v.empty=label(list,'',12,-180,374,'GameFontHighlight');v.empty:SetJustifyH('CENTER')
end

local function qualityName(self,b)
 local name=b.name
 if GetItemInfo then
  local ok,_,_,quality=pcall(GetItemInfo,b.market.itemID)
  local c=ok and quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if c and c.hex then return c.hex..name..'|r' end
 end
 return name
end
function M:RenderShopBuy()
 local s=self.shopScreen;local v=s and s.buyView;local b=self.shopBuy
 if not v or not b then return end
 v:Show()
 v.name:SetText(qualityName(self,b))
 v.icon:SetTexture(self:RowItemIcon(b,b.market.itemID))
 local com=b.commodity~=false
 v.qtyLabel:SetShown(com);v.qty:SetShown(com);v.maxButton:SetShown(com);v.itemHint:SetShown(not com)
 if com and not (v.qty.HasFocus and v.qty:HasFocus()) then v.qty:SetText(tostring(b.quantity or 0)) end
 v.cols[1]:SetText(com and 'Unit price' or 'Buyout price')
 v.cols[2]:SetText(com and '' or 'Each');v.cols[3]:SetText('Available')
 local unit,total=self:ShopBuyPrices(b)
 v.unit:SetText(unit and self:Coins(unit) or '--');v.total:SetText(total and self:Coins(total) or '--')
 local rows=b.rows or {}
 local off=math.max(0,math.min(b.offset or 0,math.max(0,#rows-ROWS)));b.offset=off
 local running=0;local before={}
 for i,r in ipairs(rows) do before[i]=running;running=running+r.quantity;if i>=off+ROWS then break end end
 for i,r in ipairs(v.rows) do
  local idx=i+off;local o=rows[idx];r.index=o and idx or nil;r:SetShown(o~=nil)
  if o then
   local selected=com and (before[idx] or 0)<(b.quantity or 0) or (not com and (b.pick or 1)==idx)
   r.sel:SetShown(selected and true or false)
   if com then
    r.c[1]:SetText(self:Coins(o.unit));r.c[2]:SetText('')
   else
    r.c[1]:SetText(self:Coins(o.total));r.c[2]:SetText(o.quantity>1 and self:Coins(o.unit) or '')
   end
   r.c[3]:SetText(tostring(o.quantity))
  end
 end
 v.empty:SetText(#rows==0 and (b.searching and 'Searching...' or (b.status or '')) or '')
 v.empty:SetShown(#rows==0)
 local ok,lines=self:ShopBuyCheck(b)
 v.buyNow:SetEnabled(ok and true or false)
 v.refresh:SetEnabled(self.ahOpen and not b.searching and true or false)
 v.status:SetText(table.concat(lines,'\n\n'))
 local unresolved=self:HasUnresolvedPurchase() and not (self.execution and self.execution.state=='pending')
 v.gotIt:SetShown(unresolved and true or false);v.didnt:SetShown(unresolved and true or false)
 local money=GetMoney and GetMoney()
 v.money:SetText(self:Finite(money,0,1e14) and ('Your gold: '..self:Coins(money)) or '')
end
