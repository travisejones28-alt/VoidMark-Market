local _,M=...
-- Auctionator-style Shopping screen (own implementation, VoidMark styling).
-- Left: shopping lists (click = open + live search) and recent searches.
-- Top: search term, Search, Add to list. Right: Price / Name / Available.
local function label(parent,text,x,y,w,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontNormalSmall');f:SetPoint('TOPLEFT',x,y)
 if w then f:SetWidth(w) end;f:SetJustifyH('LEFT');f:SetText(text or '');return f
end
local function button(parent,text,x,y,w,fn,h)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,h or 24);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local function edit(parent,x,y,w)
 local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate');e:SetPoint('TOPLEFT',x,y);e:SetSize(w,22);e:SetAutoFocus(false)
 e:SetScript('OnEscapePressed',function(f) f:ClearFocus() end);return e
end
local ROWS=15

function M:AddRecentSearch(text)
 if self.persistenceBlocked or type(text)~='string' or text=='' then return end
 local list=self.db.recentSearches
 for i=#list,1,-1 do if type(list[i])~='string' or list[i]:lower()==text:lower() then table.remove(list,i) end end
 table.insert(list,1,text);while #list>20 do table.remove(list) end
end
function M:ShopSearch(text)
 text=(text or ''):match('^%s*(.-)%s*$')
 if #text<2 then self:Print('Type at least two characters');return end
 self.shoppingListMode=false;self.selectedRow=nil;self.page=1
 self.db.settings.filter=text
 if self.shopSearch and self.shopSearch:GetText()~=text then self.shopSearch:SetText(text) end
 self:AddRecentSearch(text);self:WarmItemNames()
 self:BuildBrowseRows(text)
 if self.ahOpen then self:LiveNameSearch(text) else self.shoppingSearchStatus='Showing saved prices. Open the Auction House for live results.';self:RefreshUI() end
end
function M:OpenShoppingList(name)
 local ok,why=self:SetList(name);if not ok then self:Print(why);return end
 self.shoppingListMode=true;self.selectedRow=nil;self.page=1;self.db.settings.filter=''
 if self.shopSearch then self.shopSearch:SetText('') end
 if self.ahOpen then self:SearchShoppingList() end
 self:RefreshUI()
end
function M:ShopListNames()
 local names={'Shopping'};for name in pairs(self.db.shoppingLists) do names[#names+1]=name end
 table.sort(names,function(a,b) if a=='Shopping' then return true elseif b=='Shopping' then return false end return a:lower()<b:lower() end)
 return names
end
function M:ShopAddSelected()
 local row=self.selectedRow;if not row or row.marketKey==nil then self:Print('Select a result first');return end
 local ok,why=self:SetWatch(row.marketKey,nil);self:Print(ok and ('Added to '..self.activeList) or why)
end
function M:ShopRemoveSelected()
 local row=self.selectedRow;if not self.shoppingListMode or not row or row.marketKey==nil then self:Print('Open a list and select an item');return end
 if self:RemoveWatch(row.marketKey) then self.selectedRow=nil end
end

function M:InitializeShopScreen(f)
 local s=CreateFrame('Frame',nil,f);s:SetPoint('TOPLEFT',18,-108);s:SetSize(1004,554);s:Hide();self.shopScreen=s
 local left=self.panel(s,0,0,300,554);s.left=left
 s.tabLists=button(left,'Shopping lists',8,-8,138,function() self.shopLeft='lists';self:RefreshUI() end)
 s.tabRecent=button(left,'Recent searches',152,-8,138,function() self.shopLeft='recent';self:RefreshUI() end)
 s.leftRows={}
 for i=1,16 do
  local r=CreateFrame('Button',nil,left);r:SetPoint('TOPLEFT',8,-40-(i-1)*26);r:SetSize(250,24)
  r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  r.sel=r:CreateTexture(nil,'BACKGROUND');r.sel:SetAllPoints();r.sel:SetColorTexture(.32,.15,.5,.45)
  r.text=label(r,'',8,-6,236,'GameFontHighlight')
  r:SetScript('OnClick',function(b)
   if not b.value then return end
   if self.shopLeft=='recent' then self:ShopSearch(b.value) else self:OpenShoppingList(b.value) end
  end)
  r.go=CreateFrame('Button',nil,left);r.go:SetPoint('TOPLEFT',262,-42-(i-1)*26);r.go:SetSize(20,20)
  r.go:SetNormalTexture('Interface\\Common\\UI-Searchbox-Icon')
  r.go:SetScript('OnClick',function() if r.value then if self.shopLeft=='recent' then self:ShopSearch(r.value) else self:OpenShoppingList(r.value) end end end)
  s.leftRows[i]=r
 end
 label(left,'New list',10,-468,80,'GameFontHighlight')
 s.newList=edit(left,72,-462,140)
 local function create()
  local name=s.newList:GetText();if name=='' then return end
  s.newList:SetText('');s.newList:ClearFocus();self:OpenShoppingList(name)
 end
 s.newList:SetScript('OnEnterPressed',create)
 button(left,'Create',218,-462,74,create)
 button(left,'Import / Export',8,-500,284,function() self:ShowTransferWindow() end,26)
 -- Search bar
 local top=self.panel(s,312,0,692,48)
 label(top,'Search',12,-17,60,'GameFontHighlight')
 self.shopSearch=edit(top,66,-13,300)
 self.shopSearch:SetScript('OnEnterPressed',function(e) e:ClearFocus();self:ShopSearch(e:GetText()) end)
 button(top,'Search',376,-12,96,function() self:ShopSearch(self.shopSearch:GetText()) end)
 s.addButton=button(top,'Add to list',480,-12,110,function() self:ShopAddSelected() end)
 s.removeButton=button(top,'Remove',596,-12,88,function() self:ShopRemoveSelected() end)
 -- Results
 local res=self.panel(s,312,-56,692,458);s.results=res
 s.title=label(res,'',14,-10,660,'GameFontNormal')
 s.cols={label(res,'Price / unit',14,-32,170),label(res,'Name',190,-32,300),label(res,'Available',496,-32,90),label(res,'Updated',592,-32,90)}
 s.rows={}
 for i=1,ROWS do
  local r=CreateFrame('Button',nil,res);r:SetPoint('TOPLEFT',6,-50-(i-1)*26);r:SetSize(680,25)
  r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  r.sel=r:CreateTexture(nil,'BACKGROUND');r.sel:SetAllPoints();r.sel:SetColorTexture(.32,.15,.5,.45)
  r.icon=r:CreateTexture(nil,'ARTWORK');r.icon:SetSize(20,20);r.icon:SetPoint('LEFT',182,0)
  r.c={label(r,'',8,-7,170,'GameFontHighlight'),label(r,'',208,-7,280,'GameFontHighlight'),label(r,'',490,-7,90,'GameFontHighlight'),label(r,'',586,-7,94,'GameFontHighlight')}
  r:SetScript('OnClick',function(b) if b.data then self.selectedRow=b.data;self:RefreshUI() end end)
  r:SetScript('OnDoubleClick',function(b) if b.data then self.selectedRow=b.data;self:ShopSelected(b.data) end end)
  r:SetScript('OnEnter',function(b) self:ShowRowTooltip(b) end)
  r:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  s.rows[i]=r
 end
 res:EnableMouseWheel(true)
 res:SetScript('OnMouseWheel',function(_,d) self.page=math.max(1,(self.page or 1)-(d>0 and 1 or -1));self:RefreshUI() end)
 s.empty=label(res,'',14,-200,660,'GameFontHighlight');s.empty:SetJustifyH('CENTER')
 s.buy=button(s,'Buy...',312,-522,140,function() self:ShopSelected(self.selectedRow) end,26)
 button(s,'Price history',460,-522,140,function() self:ShowHistoryWindow(self.selectedRow) end,26)
 s.searchList=button(s,'Search this list',608,-522,160,function() self:SearchShoppingList() end,26)
 s.pageText=label(s,'',780,-528,220,'GameFontHighlightSmall');s.pageText:SetJustifyH('RIGHT')
 self.shopLeft='lists'
end

local function sourceText(o)
 if o.status=='LIVE BROWSE' or o.status=='LIVE' or o.status=='NONE' then return 'Live' end
 if o.status=='SYNCED' or o.status=='SYNC STALE' then return 'Bank' end
 return 'Scan'
end
function M:RenderShopScreen()
 local s=self.shopScreen;if not s then return end
 s:Show()
 -- Left column
 local recent=self.shopLeft=='recent'
 s.tabLists:SetEnabled(recent);s.tabRecent:SetEnabled(not recent)
 local values=recent and self.db.recentSearches or self:ShopListNames()
 for i,r in ipairs(s.leftRows) do
  local v=values[i];r.value=v;r:SetShown(v~=nil);r.go:SetShown(v~=nil)
  if v then
   r.text:SetText(v);r.sel:SetShown(not recent and self.shoppingListMode and self.activeList==v)
  end
 end
 -- Results
 local source=self:ShoppingResultRows()
 if self.shopSearch and not (self.shopSearch.HasFocus and self.shopSearch:HasFocus()) and not self.shoppingListMode then
  self.shopSearch:SetText(self.db.settings.filter or '')
 end
 s.title:SetText(self.shoppingListMode and ('List: '..self.activeList) or ((self.db.settings.filter or '')~='' and ('Results for "'..self.db.settings.filter..'"') or 'Search the Auction House'))
 local pages=math.max(1,math.ceil(#source/ROWS));self.page=math.min(self.page or 1,pages)
 for i,r in ipairs(s.rows) do
  local o=source[(self.page-1)*ROWS+i];r.data=o;r:SetShown(o~=nil)
  if o then
   r.sel:SetShown(self.selectedRow==o)
   r.icon:SetTexture(self:RowItemIcon(o,o.itemID) or 'Interface\\Icons\\INV_Misc_QuestionMark')
   local price=o.floor and o.floor>0 and self:Coins(o.floor) or (o.status=='NONE' and '|cff999999None listed|r' or '|cff999999Unknown|r')
   local age=(o.status=='LIVE BROWSE') and 'Just now' or (o.at and self:PriceAge(o.at)) or '--'
   r.c[1]:SetText(price);r.c[2]:SetText(o.name or '?');r.c[3]:SetText(o.quantity and tostring(o.quantity) or '--')
   r.c[4]:SetText(sourceText(o)..' | '..age)
  end
 end
 local empty=''
 if #source==0 then
  local f=self.db.settings.filter or ''
  empty=self.shoppingSearchStatus or (self.shoppingListMode and 'This list is empty. Search for an item, select it and click Add to list.')
   or (f~='' and ('No saved prices match "'..f..'".'..(self.ahOpen and ' Press Search to check the Auction House.' or ' Open the Auction House to search it live.')))
   or 'Type an item name and press Enter.'
 end
 s.empty:SetText(empty);s.empty:SetShown(empty~='')
 s.pageText:SetText(#source>0 and (#source..' results  |  page '..self.page..' / '..pages) or '')
 s.buy:SetEnabled(self.selectedRow~=nil and self.ahOpen and true or false)
 s.searchList:SetShown(self.shoppingListMode);s.searchList:SetEnabled(self.ahOpen and true or false)
 s.removeButton:SetShown(self.shoppingListMode)
end
