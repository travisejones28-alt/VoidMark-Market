local _,M=...
-- Auctionator-style Selling screen (own implementation, VoidMark styling).
-- Left: bag items as icon tiles grouped by type. Top: item, quantity, price
-- boxes, duration, deposit/total, Post/Skip. Right: live listings with
-- Current prices / Price history / Your history views.
local function label(parent,text,x,y,w,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontNormalSmall');f:SetPoint('TOPLEFT',x,y)
 if w then f:SetWidth(w) end;f:SetJustifyH('LEFT');f:SetText(text or '');return f
end
local function button(parent,text,x,y,w,fn,h)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,h or 24);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local function edit(parent,x,y,w,numeric)
 local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate');e:SetPoint('TOPLEFT',x,y);e:SetSize(w,22);e:SetAutoFocus(false)
 if numeric and e.SetNumeric then e:SetNumeric(true) end
 e:SetScript('OnEscapePressed',function(f) f:ClearFocus() end);return e
end
local function panel(parent,x,y,w,h)
 local p=CreateFrame('Frame',nil,parent,'BackdropTemplate');p:SetPoint('TOPLEFT',x,y);p:SetSize(w,h)
 if p.SetBackdrop then
  p:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
  p:SetBackdropColor(.045,.035,.07,.96);p:SetBackdropBorderColor(.38,.24,.6,.9)
 end
 return p
end
M.panel=panel
-- Coin-icon money like Auctionator: "1[s] 89[c]", leading zero units dropped.
local icons={'Interface\\MoneyFrame\\UI-GoldIcon','Interface\\MoneyFrame\\UI-SilverIcon','Interface\\MoneyFrame\\UI-CopperIcon'}
function M:Coins(v)
 v=tonumber(v);if not v or not self:Finite(v,-1e14,1e14) then return '--' end
 v=math.floor(v);local sign=v<0 and '-' or '';v=math.abs(v)
 local parts={math.floor(v/10000),math.floor(v/100)%100,v%100};local out={}
 for i,n in ipairs(parts) do
  if n>0 or #out>0 or i==3 then out[#out+1]=n..'|T'..icons[i]..':0:0:2:0|t' end
 end
 return sign..table.concat(out,' ')
end

-- One tile per auction identity: commodities and stacks of the same variant
-- merge into a total; the first bag slot is used to post.
function M:SellTiles(rows)
 local tiles,byKey={},{}
 for _,r in ipairs(rows or {}) do
  local k=r.marketKey
  local t=k~=nil and byKey[k]
  if t then t.count=t.count+(r.quantity or 1)
  else
   t={row=r,count=r.quantity or 1,key=k}
   local id=r.itemID;local class,classID='Other',99
   local instant=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
   if instant and id then local ok,_,typ,_,_,_,cid=pcall(instant,id);if ok and typ then class,classID=typ,tonumber(cid) or 98 end end
   t.class,t.classID=class,classID
   t.fav=k~=nil and self.db.sellFavourites[k] and true or false
   tiles[#tiles+1]=t;if k~=nil then byKey[k]=t end
  end
 end
 table.sort(tiles,function(a,b)
  if a.fav~=b.fav then return a.fav end
  if a.classID~=b.classID then return a.classID<b.classID end
  return tostring(a.row.name)<tostring(b.row.name)
 end)
 return tiles
end
function M:ToggleSellFavourite(key)
 if key==nil or self.persistenceBlocked then return end
 self.db.sellFavourites[key]=not self.db.sellFavourites[key] or nil
 self:RefreshUI()
end
function M:SkipSellItem()
 local tiles=self:SellTiles(self.sellingRows)
 if #tiles==0 then return end
 local at=0
 for i,t in ipairs(tiles) do if t.row==self.selectedRow then at=i;break end end
 local nextTile=tiles[at%#tiles+1]
 self:SelectSellRow(nextTile.row,true)
end
function M:SellMax()
 local q=self.postQuote;local r=self.selectedRow
 local max=q and q.max
 if not max and r then for _,t in ipairs(self:SellTiles(self.sellingRows)) do if t.row==r then max=t.row.quantity end end end
 if max then self.postQty:SetText(tostring(max)) end
end
function M:SetDuration(d)
 self.postDuration=d
 if not self.persistenceBlocked then self.db.settings.postDuration=d end
 self:RefreshUI()
end
function M:PickListing(entry)
 if not entry then return end
 local unit=entry.own and entry.unit or self:SuggestPostUnit(self.selectedRow,entry.unit)
 self:SetPostPrice(unit);self:RefreshUI()
end
function M:SellDeposit()
 local r=self.selectedRow;local n=tonumber(self.postQty and self.postQty:GetText())
 if not r or not self:Finite(n,1,1e9) or not self.ahOpen or not self.ReadBagSlot then return end
 local ok,b=pcall(self.ReadBagSlot,self,r);if not ok or not b then return end
 local A=C_AuctionHouse;local fn=b.commodity and A.CalculateCommodityDeposit or A.CalculateItemDeposit
 if not fn then return end
 local good,v=pcall(fn,b.commodity and r.itemID or b.loc,self.postDuration or 3,n)
 if good and self:Finite(v,0,1e12) then return v end
end
function M:PostClicked()
 local unit=self:GetPostPrice()
 if not unit or unit<1 then self:Print('Enter a price of at least 1 copper');return end
 self:ReviewPost(self.selectedRow,tonumber(self.postQty:GetText()),unit,self.postDuration)
end

function M:InitializeSellScreen(f)
 local s=CreateFrame('Frame',nil,f);s:SetPoint('TOPLEFT',18,-108);s:SetSize(1004,554);s:Hide();self.sellScreen=s
 -- Bag panel
 local bags=panel(s,0,0,300,554);s.bags=bags
 label(bags,'YOUR ITEMS',12,-10,200,'GameFontNormal')
 s.bagHint=label(bags,'Right-click: favourite',150,-12,140,'GameFontDisableSmall')
 local scroll=CreateFrame('ScrollFrame',nil,bags,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',8,-30);scroll:SetSize(262,514)
 local child=CreateFrame('Frame',nil,scroll);child:SetSize(262,514);scroll:SetScrollChild(child);s.bagChild=child
 s.tiles={};s.headers={}
 -- Header
 local h=panel(s,312,0,692,148);s.header=h
 s.icon=h:CreateTexture(nil,'ARTWORK');s.icon:SetSize(44,44);s.icon:SetPoint('TOPLEFT',12,-12)
 s.name=label(h,'Select an item',66,-14,280,'GameFontNormalLarge')
 label(h,'Quantity',66,-48,70,'GameFontHighlight')
 self.postQty=edit(h,140,-44,60,true);self.postQty:SetText('1')
 button(h,'Max',206,-44,50,function() self:SellMax() end,22)
 label(h,'Unit price',66,-80,70,'GameFontHighlight')
 self.postGold=edit(h,140,-76,66,true);label(h,'g',209,-81,10,'GameFontHighlight')
 self.postSilver=edit(h,222,-76,32,true);label(h,'s',257,-81,10,'GameFontHighlight')
 self.postCopper=edit(h,270,-76,32,true);label(h,'c',305,-81,10,'GameFontHighlight')
 for _,e in ipairs({self.postQty,self.postGold,self.postSilver,self.postCopper}) do
  e:SetScript('OnTextChanged',function() if self.sellScreen:IsShown() then self:UpdateSellSummary() end end)
  e:SetScript('OnEnterPressed',function(x) x:ClearFocus();self:PostClicked() end)
 end
 label(h,'Duration',350,-14,80,'GameFontHighlight')
 s.durations={}
 for i,hours in ipairs({2,8,24}) do
  local c=CreateFrame('CheckButton',nil,h,'UICheckButtonTemplate');c:SetPoint('TOPLEFT',346+(i-1)*58,-30);c:SetSize(24,24)
  c:SetScript('OnClick',function() self:SetDuration(i) end);s.durations[i]=c
  label(h,hours..'h',372+(i-1)*58,-36,30,'GameFontHighlight')
 end
 s.post=button(h,'Post',350,-68,110,function() self:PostClicked() end,26)
 button(h,'Skip',466,-68,80,function() self:SkipSellItem() end,26)
 label(h,'Deposit',570,-14,110);s.deposit=label(h,'--',570,-30,115,'GameFontHighlight')
 label(h,'Total price',570,-52,110);s.total=label(h,'--',570,-68,115,'GameFontHighlight')
 label(h,'Never below',66,-116,80,'GameFontHighlightSmall')
 s.minimum=edit(h,148,-110,66,false)
 s.minimum:SetScript('OnEnterPressed',function(e)
  e:ClearFocus();local r=self.selectedRow
  if not r or r.marketKey==nil then return end
  local raw=e:GetText();local g=tonumber(raw)
  if raw~='' and (not g or g<=0) then self:Print('Minimum is gold, e.g. 1.25 (blank clears it)');return end
  local ok,why=self:SetSellFloor(r.marketKey,raw~='' and math.floor(g*10000+0.5) or nil)
  self:Print(ok and 'Minimum saved' or why)
 end)
 label(h,'g',217,-115,10,'GameFontHighlightSmall')
 s.info=label(h,'',232,-116,450,'GameFontHighlightSmall')
 -- Listings
 local l=panel(s,312,-156,692,358);s.list=l
 s.cols={label(l,'Unit price',14,-10,200),label(l,'Available',230,-10,120),label(l,'Total',370,-10,180),label(l,'Yours?',580,-10,90)}
 s.rows={}
 for i=1,13 do
  local r=CreateFrame('Button',nil,l);r:SetPoint('TOPLEFT',6,-28-(i-1)*25);r:SetSize(680,24)
  r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  r.c={label(r,'',8,-6,210,'GameFontHighlight'),label(r,'',224,-6,130,'GameFontHighlight'),label(r,'',364,-6,200,'GameFontHighlight'),label(r,'',574,-6,90,'GameFontHighlight')}
  r:SetScript('OnClick',function(b) if self.sellMode=='current' then self:PickListing(b.entry) end end)
  s.rows[i]=r
 end
 l:EnableMouseWheel(true)
 l:SetScript('OnMouseWheel',function(_,d) self.sellListPage=math.max(1,(self.sellListPage or 1)-(d>0 and 1 or -1));self:RefreshUI() end)
 s.empty=label(l,'',14,-160,660,'GameFontHighlight');s.empty:SetJustifyH('CENTER')
 -- Sub-tabs
 s.modes={}
 for i,m in ipairs({{'current','Current prices'},{'history','Price history'},{'mine','Your history'}}) do
  s.modes[m[1]]=button(s,m[2],312+(i-1)*150,-522,144,function() self.sellMode=m[1];self.sellListPage=1;self:RefreshUI() end,26)
 end
 button(s,'Refresh',884,-522,120,function()
  self:RefreshInventory()
  if self.selectedRow and self.ahOpen then self.postQuote=nil;self:CheckPost(self.selectedRow) end
 end,26)
 self.sellMode='current';self.postDuration=self:PostDuration()
end

local function money(self,v) return self:Coins(v) end
function M:UpdateSellSummary()
 local s=self.sellScreen;if not s then return end
 local n=tonumber(self.postQty:GetText());local unit=self:GetPostPrice()
 s.total:SetText(unit and n and money(self,unit*n) or '--')
 local dep=self:SellDeposit();s.deposit:SetText(dep and money(self,dep) or '--')
end
function M:SellListRows()
 local mode=self.sellMode or 'current';local r=self.selectedRow;local out={}
 if not r then return out end
 if mode=='current' then
  local q=self.postQuote
  if q and q.listings then
   -- Merge equal prices like the native list; own units are shown separately.
   local last
   for _,e in ipairs(q.listings) do
    if last and last.unit==e.unit and last.own==e.own then last.quantity=last.quantity+e.quantity
    else last={unit=e.unit,quantity=e.quantity,own=e.own};out[#out+1]=last end
   end
  end
 elseif mode=='history' then
  local m=r.marketKey~=nil and self.db.market[r.marketKey]
  local hist=m and m.history or {}
  for i=#hist,math.max(1,#hist-60),-1 do local e=hist[i];if type(e)=='table' then out[#out+1]={at=e.at,unit=e.median or e.floor,quantity=e.quantity} end end
 else
  for _,e in ipairs(r.marketKey~=nil and self.db.postHistory[r.marketKey] or {}) do out[#out+1]=e end
 end
 return out
end
function M:RenderSellScreen()
 local s=self.sellScreen;if not s then return end
 s:Show()
 local rows=self.sellingRows or {}
 -- Re-attach the selection to the refreshed bag rows.
 if self.selectedRow then
  local sel=self.selectedRow;local found
  for _,r in ipairs(rows) do if r.bag==sel.bag and r.slot==sel.slot and r.marketKey==sel.marketKey then found=r;break end end
  if found and found~=sel then
   self.selectedRow=found
   if self.postQuote and self.postQuote.row==sel then self.postQuote.row=found end
  end
 end
 -- Bag tiles
 local tiles=self:SellTiles(rows);local y,col,group=0,0,nil;local hi,ti=0,0
 for _,t in ipairs(tiles) do
  local g=t.fav and 'Favourites' or t.class
  if g~=group then
   group=g;if col>0 then y=y-40;col=0 end
   hi=hi+1;local hd=s.headers[hi]
   if not hd then hd=label(s.bagChild,'',2,0,250,'GameFontNormal');s.headers[hi]=hd end
   hd:ClearAllPoints();hd:SetPoint('TOPLEFT',2,y-2);hd:SetText(g);hd:Show();y=y-20
  end
  ti=ti+1;local b=s.tiles[ti]
  if not b then
   b=CreateFrame('Button',nil,s.bagChild);b:SetSize(36,36)
   b.tex=b:CreateTexture(nil,'ARTWORK');b.tex:SetAllPoints()
   b.sel=b:CreateTexture(nil,'OVERLAY');b.sel:SetAllPoints();b.sel:SetColorTexture(.62,.35,1,.35)
   b.count=b:CreateFontString(nil,'OVERLAY','NumberFontNormal');b.count:SetPoint('BOTTOMRIGHT',-2,2)
   b:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square')
   if b.RegisterForClicks then b:RegisterForClicks('LeftButtonUp','RightButtonUp') end
   b:SetScript('OnClick',function(btn,mouse)
    if not btn.tile then return end
    if mouse=='RightButton' then self:ToggleSellFavourite(btn.tile.key) else self:SelectSellRow(btn.tile.row,true) end
   end)
   b:SetScript('OnEnter',function(btn)
    local r=btn.tile and btn.tile.row
    if r and GameTooltip then GameTooltip:SetOwner(btn,'ANCHOR_RIGHT');if GameTooltip.SetBagItem then GameTooltip:SetBagItem(r.bag,r.slot) end;GameTooltip:Show() end
   end)
   b:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
   s.tiles[ti]=b
  end
  b.tile=t;b:ClearAllPoints();b:SetPoint('TOPLEFT',col*38,y)
  b.tex:SetTexture(t.row.icon or self:RowItemIcon(t.row,t.row.itemID) or 'Interface\\Icons\\INV_Misc_QuestionMark')
  b.count:SetText(t.count>1 and tostring(t.count) or '');b.sel:SetShown(self.selectedRow==t.row);b:Show()
  col=col+1;if col>=7 then col=0;y=y-38 end
 end
 for i=ti+1,#s.tiles do s.tiles[i]:Hide();s.tiles[i].tile=nil end
 for i=hi+1,#s.headers do s.headers[i]:Hide() end
 s.bagChild:SetHeight(math.max(514,-y+40))
 -- Header
 local r=self.selectedRow
 s.name:SetText(r and r.name or (#tiles==0 and 'No sellable items in your bags' or 'Select an item'))
 s.icon:SetTexture(r and (r.icon or self:RowItemIcon(r,r.itemID)) or 'Interface\\Icons\\INV_Misc_QuestionMark')
 for i,c in ipairs(s.durations) do c:SetChecked(self.postDuration==i) end
 s.post:SetEnabled(r~=nil and self.ahOpen and not self.tradePending and true or false)
 local floor=r and r.marketKey~=nil and self.db.sellFloors[r.marketKey]
 if not (s.minimum.HasFocus and s.minimum:HasFocus()) then s.minimum:SetText(floor and self:FormatGoldInput(floor):gsub('%.?0+$','') or '') end
 local q=self.postQuote
 local info
 if not r then info='Click an item on the left. Its live price is checked automatically.'
 elseif not self.ahOpen then info='Open the Auction House to check prices and post.'
 elseif q and not q.at then info='Checking live price...'
 elseif q then info=q.floor and ('Lowest other: '..money(self,q.floor)..(q.atMinimum and ' | held at your minimum' or (' | your price undercuts by '..money(self,self.db.settings.sellUndercut or 1)))) or 'No other listings - your price sets the market.'
 else info='Click Refresh to check the live price.' end
 s.info:SetText(info)
 self:UpdateSellSummary()
 -- Listings
 local mode=self.sellMode or 'current'
 for k,b in pairs(s.modes) do b:SetEnabled(k~=mode) end
 local heads=mode=='current' and {'Unit price','Available','Total','Yours?'} or mode=='history' and {'Date','Median / unit','Listed','' } or {'Date','Your price / unit','Quantity','Duration'}
 for i,c in ipairs(s.cols) do c:SetText(heads[i]) end
 local list=self:SellListRows();local pages=math.max(1,math.ceil(#list/13))
 self.sellListPage=math.min(self.sellListPage or 1,pages)
 for i,row in ipairs(s.rows) do
  local e=list[(self.sellListPage-1)*13+i];row.entry=e;row:SetShown(e~=nil)
  if e then
   local cells
   if mode=='current' then cells={money(self,e.unit),tostring(e.quantity),money(self,e.unit*e.quantity),e.own and '|cff72e7aaYes|r' or 'No'}
   elseif mode=='history' then cells={date('%b %d %H:%M',e.at or 0),money(self,e.unit),tostring(e.quantity or '--'),''}
   else cells={date('%b %d %H:%M',e.at or 0),money(self,e.unit),tostring(e.quantity or '--'),e.duration and (({2,8,24})[e.duration]..'h') or ''} end
   for j=1,4 do row.c[j]:SetText(cells[j]) end
  end
 end
 local empty=''
 if r and #list==0 then
  empty=mode=='current' and (q and q.at and 'No other listings for this item.' or 'Live listings appear here after the price check.')
   or mode=='history' and 'No scan history for this item yet.' or 'You have not posted this item with VoidMark yet.'
 end
 s.empty:SetText(empty);s.empty:SetShown(empty~='')
end
