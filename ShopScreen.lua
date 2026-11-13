local _,M=...
-- Shopping screen laid out like Auctionator's Shopping tab (behavior reference:
-- Auctionator 342 Source/Tabs/Shopping; independent implementation, VoidMark
-- styling, no Auctionator code or art).
--  Top:    Search Term [box][x]  Search (Cancel while searching)  More...  Add to List
--  Left:   Shopping Lists | Recent Searches mini tabs. Lists expand like folders
--          (+/-) to show their items; list rows have search / rename / delete,
--          item rows have delete. Recents have delete / copy to list.
--          New List, Import, Export under the panel.
--  Right:  sortable Price | Name | Available results that scroll.
--          Left-click = buy view, right-click = price history,
--          shift-click = put the name in the search box. Export Results below.
-- Market lists hold items (and sync between your accounts) plus, since 1.14,
-- search terms like "of the Monkey" (kept on this character; see Deals.lua).
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
local ICON={search='Interface\\Common\\UI-Searchbox-Icon',rename='Interface\\Buttons\\UI-GuildButton-PublicNote-Up',
 delete='Interface\\Buttons\\UI-GroupLoot-Pass-Up',copy='Interface\\PaperDollInfoFrame\\Character-Plus',
 plus='Interface\\Buttons\\UI-PlusButton-Up',minus='Interface\\Buttons\\UI-MinusButton-Up'}
local PURPLE,DIM='|cffc8a0ff','|cff8f8f8f'
local LEFT_ROWS,ROWS,ROW_H=20,19,22
M.SHOP_RESULT_ROWS=ROWS

-- Recent searches ------------------------------------------------------------
function M:AddRecentSearch(text)
 if self.persistenceBlocked or type(text)~='string' or text=='' then return end
 local list=self.db.recentSearches
 for i=#list,1,-1 do if type(list[i])~='string' or list[i]:lower()==text:lower() then table.remove(list,i) end end
 table.insert(list,1,text);while #list>20 do table.remove(list) end
end
function M:DeleteRecentSearch(text)
 local list=self.db.recentSearches
 for i=#list,1,-1 do if list[i]==text then table.remove(list,i) end end
 self:RefreshUI()
end
-- Item ID whose name matches the text exactly (results, saved prices or names).
function M:ShopFindItemByName(text)
 local want=tostring(text or ''):lower();if want=='' then return end
 for _,r in ipairs(self.browseRows or {}) do if (r.name or ''):lower()==want then return r.marketKey,r.name end end
 for key,m in pairs(self.db.market) do if type(m)=='table' and (m.name or ''):lower()==want then return key,m.name end end
 for id,name in pairs(self.db.itemNames or {}) do if type(name)=='string' and name:lower()==want then return id,name end end
end
function M:ShopCopyRecent(text)
 if not self.shopExpanded then self:Print('Open a shopping list first, then copy the search into it');return false end
 local key,name=self:ShopFindItemByName(text)
 if not key then local ok,why=self:AddShopTerm(self.shopExpanded,text);self:Print(ok and ('Search term "'..text..'" added to '..self.shopExpanded) or why);return ok end
 local ok,why=self:SetWatch(key,nil);self:Print(ok and (name..' added to '..self.activeList) or why);return ok
end

-- Clicking a search term inside an open list sweeps just that term.
function M:SearchListTerm(list,term)
 if self.ShopBuyClose then self:ShopBuyClose() end
 if self.StopTermSearch then self:StopTermSearch() end
 self.shoppingListMode=true;self.shopOnlyKey=nil;self.shopOnlyTerm=term;self.selectedRow=nil;self.shopScroll=0;self.termRows=nil
 if self.ahOpen then self:SearchShopTerms(list,term) else self:Print('Open the Auction House to search') end
 self:RefreshUI()
end

-- Searching ------------------------------------------------------------------
function M:ShopSearch(text,keepFilters)
 text=(text or ''):match('^%s*(.-)%s*$')
 if #text<2 then self:Print('Type at least two characters');return end
 if self.ShopBuyClose then self:ShopBuyClose() end
 if not keepFilters then self.shopFilters=nil end
 self.shopOnlyTerm=nil
 self.shoppingListMode=false;self.shopOnlyKey=nil;self.selectedRow=nil;self.page=1;self.shopScroll=0
 self.db.settings.filter=text
 if self.shopSearch and self.shopSearch:GetText()~=text then self.shopSearch:SetText(text) end
 self:AddRecentSearch(text);self:WarmItemNames()
 self:BuildBrowseRows(text)
 if self.ahOpen then self:LiveNameSearch(text) else self.shoppingSearchStatus='Showing saved prices. Open the Auction House for live results.';self:RefreshUI() end
end
function M:ShopSearching()
 local r=self.listSearch
 if r and not r.finished then return true end
 if self.TermSearchRunning and self:TermSearchRunning() then return true end
 local st=self.shoppingSearchStatus
 return type(st)=='string' and st:find('^Searching the Auction House') and true or false
end
function M:ShopStopSearch()
 self.listSearch=nil;self.nameSearch=nil
 if self.StopTermSearch then self:StopTermSearch() end
 if self:ShopSearching() then self:CancelJob('browse');self.shoppingSearchStatus=nil end
 self:RefreshUI()
end
-- The Search button: cancels a running search; with an empty box and an open
-- list it searches the whole list; otherwise searches the typed name.
function M:ShopSearchClicked()
 if self:ShopSearching() then return self:ShopStopSearch() end
 local text=self.shopSearch and self.shopSearch:GetText() or ''
 if text:match('^%s*$') and self.shopExpanded then return self:OpenShoppingList(self.shopExpanded) end
 self:ShopSearch(text)
end

-- Lists ----------------------------------------------------------------------
function M:OpenShoppingList(name)
 local ok,why=self:SetList(name);if not ok then self:Print(why);return end
 if self.ShopBuyClose then self:ShopBuyClose() end
 self.shopExpanded=name;self.shopOnlyKey=nil;self.shopOnlyTerm=nil
 self.shoppingListMode=true;self.selectedRow=nil;self.page=1;self.shopScroll=0;self.db.settings.filter=''
 if self.shopSearch then self.shopSearch:SetText('') end
 if self.StopTermSearch then self:StopTermSearch() end
 self.termRows=nil
 if self.ahOpen then
  local terms=self.ShopTerms and self:ShopTerms(name) or {}
  if next(self:ListBook(name) or {})~=nil or #terms==0 then self:SearchShoppingList() end
  if #terms>0 then self:SearchShopTerms(name) end
 end
 self:RefreshUI()
end
function M:CollapseShoppingList()
 self.shopExpanded=nil;self.listSearch=nil;self.termRows=nil
 if self.StopTermSearch then self:StopTermSearch() end
 self:RefreshUI()
end
function M:ToggleShoppingList(name)
 if self.shopExpanded==name then self:CollapseShoppingList() else self:OpenShoppingList(name) end
end
-- Clicking an item inside an open list searches just that item.
function M:SearchListEntry(key)
 if self.ShopBuyClose then self:ShopBuyClose() end
 self.shopOnlyTerm=nil
 self.shoppingListMode=true;self.shopOnlyKey=key;self.selectedRow=nil;self.shopScroll=0
 if self.ahOpen then self:SearchShoppingList(key) end
 self:RefreshUI()
end
function M:ShopListNames()
 local names={'Shopping'};for name in pairs(self.db.shoppingLists) do names[#names+1]=name end
 table.sort(names,function(a,b) if a=='Shopping' then return true elseif b=='Shopping' then return false end return a:lower()<b:lower() end)
 return names
end
-- Rows shown in the lists panel: list headers, plus the open list's items.
function M:ShopTreeRows()
 local out={}
 for _,name in ipairs(self:ShopListNames()) do
  out[#out+1]={type='list',name=name}
  if self.shopExpanded==name then
   local items={}
   for key,entry in pairs(self:ListBook(name) or {}) do
    if type(entry)=='table' then
     local m=self.db.market[key]
     items[#items+1]={type='item',list=name,key=key,itemID=m and m.itemID or entry.itemID,name=(m and m.name) or entry.name or tostring(key)}
    end
   end
   table.sort(items,function(a,b) return tostring(a.name):lower()<tostring(b.name):lower() end)
   for _,i in ipairs(items) do out[#out+1]=i end
   local terms=self.ShopTerms and self:ShopTerms(name) or {}
   for _,t in ipairs(terms) do out[#out+1]={type='term',list=name,text=t} end
   if #items==0 and #terms==0 then out[#out+1]={type='empty'} end
  end
 end
 return out
end
-- Text prompt (New List / Rename). Falls back to printing if dialogs are missing.
function M:AskShopText(prompt,default,accept)
 if not StaticPopupDialogs or not StaticPopup_Show then self:Print('Dialog unavailable');return end
 StaticPopupDialogs.VOIDMARKMARKET_SHOPTEXT=StaticPopupDialogs.VOIDMARKMARKET_SHOPTEXT or {
  text='%s',button1=ACCEPT or 'Accept',button2=CANCEL or 'Cancel',hasEditBox=true,maxLetters=24,timeout=0,whileDead=true,
  hideOnEscape=true,preferredIndex=3,
  OnShow=function(f,data) local e=f.editBox or f.EditBox;if e and data then e:SetText(data.default or '');e:HighlightText() end end,
  OnAccept=function(f,data) local e=f.editBox or f.EditBox;if data and data.accept then data.accept(e and e:GetText() or '') end end,
  EditBoxOnEnterPressed=function(e,data) local f=e:GetParent();if data and data.accept then data.accept(e:GetText()) end;f:Hide() end}
 StaticPopup_Show('VOIDMARKMARKET_SHOPTEXT',prompt,nil,{default=default,accept=accept})
end
function M:AskShopConfirm(prompt,accept)
 if not StaticPopupDialogs or not StaticPopup_Show then self:Print('Dialog unavailable');return end
 StaticPopupDialogs.VOIDMARKMARKET_SHOPCONFIRM=StaticPopupDialogs.VOIDMARKMARKET_SHOPCONFIRM or {
  text='%s',button1=ACCEPT or 'Accept',button2=CANCEL or 'Cancel',timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
  OnAccept=function(_,fn) if type(fn)=='function' then fn() end end}
 StaticPopup_Show('VOIDMARKMARKET_SHOPCONFIRM',prompt,nil,accept)
end
function M:NewShoppingList()
 self:AskShopText('New shopping list name:','',function(name)
  name=tostring(name or ''):match('^%s*(.-)%s*$')
  if name~='' then self:OpenShoppingList(name) end
 end)
end
-- Delete a list: entries are removed through the normal (synced) path.
function M:DeleteShoppingList(name)
 if name=='Shopping' or not self.db.shoppingLists[name] then self:Print('The main Shopping list can be emptied but not deleted');return false end
 for key in pairs(self.db.shoppingLists[name]) do self:PublishWatch(name,key,nil) end
 self.db.shoppingLists[name]=nil
 if type(self.db.shopTerms)=='table' then self.db.shopTerms[name]=nil end
 if self.shopExpanded==name then self.shopExpanded=nil end
 if self.activeList==name then self.activeList='Shopping';self.db.activeList='Shopping';self.shoppingListMode=false end
 self:RefreshUI();return true
end
function M:RenameShoppingList(old,new)
 new=tostring(new or ''):match('^%s*(.-)%s*$')
 if old=='Shopping' then self:Print('The main Shopping list cannot be renamed');return false end
 if new=='' or new==old then return false end
 if self.db.shoppingLists[new] then self:Print('A list called '..new..' already exists');return false end
 local book=self.db.shoppingLists[old];if not book then return false end
 if not self:ListBook(new,true) then self:Print('Use a list name of 1-24 characters (24 lists maximum)');return false end
 for key,entry in pairs(book) do
  if type(entry)=='table' then self.db.shoppingLists[new][key]=entry;self:PublishWatch(new,key,entry) end
 end
 for _,t in ipairs(self.ShopTerms and self:ShopTerms(old) or {}) do self:AddShopTerm(new,t) end
 self:DeleteShoppingList(old)
 self:OpenShoppingList(new);return true
end
function M:ShopAddSelected()
 local row=self.shopBuy and {marketKey=self.shopBuy.key} or self.selectedRow
 if not row and not self.shoppingListMode and #(self.browseRows or {})==1 then row=self.browseRows[1] end
 if not row or row.marketKey==nil then
  local text=self.shopSearch and self.shopSearch:GetText();if type(text)~='string' then text='' end
  if self.shopExpanded and not text:match('^%s*$') then
   local ok,why=self:AddShopTerm(self.shopExpanded,text)
   self:Print(ok and ('Search term "'..text:match('^%s*(.-)%s*$')..'" added to '..self.shopExpanded) or why);return
  end
  self:Print('Select a result first');return
 end
 local ok,why=self:SetWatch(row.marketKey,nil);self:Print(ok and ('Added to '..self.activeList) or why)
end
function M:ShopRemoveSelected()
 local row=self.selectedRow;if not self.shoppingListMode or not row or row.marketKey==nil then self:Print('Open a list and select an item');return end
 if self:RemoveWatch(row.marketKey) then self.selectedRow=nil end
end

-- Results --------------------------------------------------------------------
local SORT={
 price=function(r) return (r.floor and r.floor>0) and r.floor or math.huge end,
 name=function(r) return tostring(r.name or ''):lower() end,
 available=function(r) return tonumber(r.quantity) or -1 end,
 deal=function(r) return M:DealRatio(r) or math.huge end,
 level=function(r) return M:RowLevel(r) or math.huge end}
function M:ShopSortBy(field)
 local s=self.shopSort or {field='price',dir=1}
 if s.field==field then s.dir=-s.dir else s={field=field,dir=1} end
 self.shopSort=s;self.shopScroll=0;self:RefreshUI()
end
-- Visible result rows: list/search source, single-entry and More... filters, sorted.
function M:ShopVisibleRows()
 local out={}
 local f=self.shopFilters
 for _,r in ipairs(self:ShoppingResultRows()) do
  local keep=true
  if self.shoppingListMode and self.shopOnlyKey~=nil and r.marketKey~=self.shopOnlyKey then keep=false end
  if self.shoppingListMode and self.shopOnlyTerm~=nil and r.term~=self.shopOnlyTerm then keep=false end
  if keep and f and not self.shoppingListMode then
   if f.exact and (r.name or ''):lower()~=(self.db.settings.filter or ''):lower() then keep=false end
   if f.maxPrice and not (r.floor and r.floor>0 and r.floor<=f.maxPrice) then keep=false end
   if f.minQuantity and not ((tonumber(r.quantity) or 0)>=f.minQuantity) then keep=false end
  end
  -- The Level box filters every search result, saved prices included (it
  -- used to apply only to live AH searches). Your own list items always show.
  -- Shopping-list results from search terms follow it too (changing the box
  -- filters what's already on screen); exact items you added always show.
  if keep and not self.snipeView and r.itemID and self.LevelAllowed and (not self.shoppingListMode or r.term)
   and not self:LevelAllowed(r.itemID) then keep=false end
  if keep then out[#out+1]=r end
 end
 local s=self.shopSort or {field='price',dir=1};local key=SORT[s.field] or SORT.price
 table.sort(out,function(a,b)
  local av,bv=key(a),key(b)
  if av~=bv then if s.dir>0 then return av<bv else return av>bv end end
  return tostring(a.marketKey)<tostring(b.marketKey)
 end)
 return out
end
function M:ShopRowClicked(row,mouse)
 if not row then return end
 if mouse=='RightButton' then self.selectedRow=row;self:ShowHistoryWindow(row);self:RefreshUI();return end
 if IsShiftKeyDown and IsShiftKeyDown() then
  if self.shopSearch then self.shopSearch:SetText(row.name or '') end
  return
 end
 self.selectedRow=row
 if self.ahOpen then self:ShopBuyOpen(row) end
 self:RefreshUI()
end
function M:ShopResultsCSV()
 local lines={'Price,Name,Available'}
 for _,r in ipairs(self:ShopVisibleRows()) do
  local name=tostring(r.name or ''):gsub('"','""')
  lines[#lines+1]=table.concat({(r.floor and r.floor>0) and tostring(r.floor) or '','"'..name..'"',tostring(r.quantity or '')},',')
 end
 return table.concat(lines,'\n')
end
function M:ShowShopExport()
 self:ShowTransferWindow()
 if self.transferEdit then self.transferEdit:SetText(self:ShopResultsCSV());self.transferEdit:SetFocus();self.transferEdit:HighlightText() end
 if self.transferStatus then self.transferStatus:SetText('Results as CSV (price in copper). Ctrl+C to copy.') end
end

-- More... (extended search) ----------------------------------------------------
function M:ShowShopMore()
 local s=self.shopScreen;if not s then return end
 local d=s.more
 if not d then
  d=self.panel(s,312,-40,340,190);d:SetFrameLevel((s:GetFrameLevel() or 1)+20);s.more=d
  label(d,PURPLE..'EXTENDED SEARCH|r',14,-12,300,'GameFontNormal')
  label(d,'Search term',14,-40,100,'GameFontHighlightSmall');d.term=edit(d,120,-34,200)
  d.exact=CreateFrame('CheckButton',nil,d,'UICheckButtonTemplate');d.exact:SetPoint('TOPLEFT',112,-60);d.exact:SetSize(24,24)
  label(d,'Exact name',14,-66,100,'GameFontHighlightSmall')
  label(d,'Max price (gold)',14,-96,100,'GameFontHighlightSmall');d.maxPrice=edit(d,120,-90,80)
  label(d,'Min available',14,-124,100,'GameFontHighlightSmall');d.minQty=edit(d,120,-118,80)
  button(d,'Search',14,-152,150,function()
   local gold=tonumber(d.maxPrice:GetText());local qty=tonumber(d.minQty:GetText())
   local f={exact=d.exact:GetChecked() and true or nil,maxPrice=gold and gold>0 and math.floor(gold*10000+0.5) or nil,
    minQuantity=qty and qty>0 and math.floor(qty) or nil}
   self.shopFilters=(f.exact or f.maxPrice or f.minQuantity) and f or nil
   d:Hide();self:ShopSearch(d.term:GetText(),true)
  end)
  button(d,'Cancel',176,-152,150,function() d:Hide() end)
 end
 d.term:SetText(self.shopSearch and self.shopSearch:GetText() or '')
 local f=self.shopFilters or {}
 d.exact:SetChecked(f.exact and true or false)
 d.maxPrice:SetText(f.maxPrice and tostring(f.maxPrice/10000) or '');d.minQty:SetText(f.minQuantity and tostring(f.minQuantity) or '')
 d:Show()
end

-- Frame ------------------------------------------------------------------------
local function optionButton(parent,texture,tip,x)
 local o=CreateFrame('Button',nil,parent);o:SetPoint('RIGHT',parent,'RIGHT',x,0);o:SetSize(18,18)
 o.icon=o:CreateTexture(nil,'ARTWORK');o.icon:SetAllPoints();o.icon:SetTexture(texture);o.tip=tip
 o:SetScript('OnEnter',function(b) b.icon:SetAlpha(.55);if GameTooltip then GameTooltip:SetOwner(b,'ANCHOR_RIGHT');GameTooltip:SetText(b.tip,1,1,1);GameTooltip:Show() end end)
 o:SetScript('OnLeave',function(b) b.icon:SetAlpha(1);if GameTooltip then GameTooltip:Hide() end end)
 return o
end
local function miniTab(parent,text,x,fn)
 local t=CreateFrame('Button',nil,parent,'BackdropTemplate');t:SetPoint('TOPLEFT',x,-42);t:SetSize(136,24)
 if t.SetBackdrop then t:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=10,insets={left=2,right=2,top=2,bottom=2}}) end
 t.text=label(t,text,0,-6,136,'GameFontNormalSmall');t.text:SetJustifyH('CENTER')
 t:SetScript('OnClick',fn)
 function t:SetSelected(on)
  if self.SetBackdropColor then
   if on then self:SetBackdropColor(.32,.15,.5,.95);self:SetBackdropBorderColor(.66,.4,.95,1)
   else self:SetBackdropColor(.06,.04,.09,.9);self:SetBackdropBorderColor(.32,.2,.5,.8) end
  end
  self.text:SetTextColor(on and 1 or .7,on and .9 or .65,on and 1 or .8)
 end
 return t
end

function M:InitializeShopScreen(f)
 local s=CreateFrame('Frame',nil,f);s:SetPoint('TOPLEFT',18,-108);s:SetSize(1004,554);s:Hide();self.shopScreen=s
 -- Top search bar (full width)
 label(s,'Search Term:',4,-10,96,'GameFontNormal')
 self.shopSearch=edit(s,104,-5,200)
 self.shopSearch:SetScript('OnEnterPressed',function(e) e:ClearFocus();self:ShopSearchClicked() end)
 s.reset=CreateFrame('Button',nil,s);s.reset:SetPoint('TOPLEFT',308,-7);s.reset:SetSize(18,18)
 s.reset.icon=s.reset:CreateTexture(nil,'ARTWORK');s.reset.icon:SetAllPoints();s.reset.icon:SetTexture(ICON.delete)
 s.reset:SetScript('OnClick',function() self.shopSearch:SetText('');self.shopFilters=nil;self:RefreshUI() end)
 s.searchButton=button(s,'Search',332,-4,96,function() self:ShopSearchClicked() end)
 s.moreButton=button(s,'More...',432,-4,90,function() self:ShowShopMore() end)
 s.addButton=button(s,'Add to List',526,-4,110,function() self:ShopAddSelected() end)
 -- Mispost sniper (Snipe.lua): on/off, and the hits list.
 s.snipeButton=button(s,'Snipe',800,-4,96,function() if self.ToggleSnipe then self:ToggleSnipe();if self.snipe and self.snipe.on then self:ShowSnipeHits() end end end)
 s.snipeHits=button(s,'Hits',900,-4,104,function() if self.ShowSnipeHits then self:ShowSnipeHits() end end)
 -- Level range for every Shopping search (blank = no limit).
 label(s,'Level:',652,-10,44,'GameFontNormal')
 s.minLevel=edit(s,700,-5,34);label(s,'-',740,-10,10,'GameFontNormal');s.maxLevel=edit(s,754,-5,34)
 local function saveLevels() self:SetShopLevelRange(s.minLevel:GetText(),s.maxLevel:GetText()) end
 for _,e in ipairs({s.minLevel,s.maxLevel}) do
  if e.SetNumeric then e:SetNumeric(true) end;if e.SetMaxLetters then e:SetMaxLetters(2) end
  e:SetScript('OnEnterPressed',function(b) b:ClearFocus();saveLevels() end)
  e:SetScript('OnEditFocusLost',function() saveLevels() end)
 end
 -- Left: mini tabs + lists / recents panel
 s.tabLists=miniTab(s,'Shopping Lists',10,function() self.shopLeft='lists';self.shopLeftOffset=0;self:RefreshUI() end)
 s.tabRecent=miniTab(s,'Recent Searches',148,function() self.shopLeft='recent';self.shopLeftOffset=0;self:RefreshUI() end)
 local left=self.panel(s,0,-66,290,450);s.left=left
 s.leftRows={}
 for i=1,LEFT_ROWS do
  local r=CreateFrame('Button',nil,left);r:SetPoint('TOPLEFT',4,-5-(i-1)*ROW_H);r:SetSize(278,ROW_H-1)
  if r.RegisterForClicks then r:RegisterForClicks('LeftButtonUp','RightButtonUp') end
  r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  r.sel=r:CreateTexture(nil,'BACKGROUND');r.sel:SetAllPoints();r.sel:SetColorTexture(.32,.15,.5,.45)
  r.text=label(r,'',10,-4,200,'GameFontHighlight')
  r.opt1=optionButton(r,ICON.search,'Search',-2)
  r.opt2=optionButton(r,ICON.rename,'Rename',-24)
  r.opt3=optionButton(r,ICON.delete,'Delete',-46)
  r:SetScript('OnClick',function(b,mouse)
   local e=b.entry;if not e then return end
   if mouse=='RightButton' then if self.shopExpanded then self:CollapseShoppingList() end;return end
   if e.type=='list' then self:ToggleShoppingList(e.name)
   elseif e.type=='item' then self:SearchListEntry(e.key)
   elseif e.type=='term' then self:SearchListTerm(e.list,e.text)
   elseif e.type=='recent' then self:ShopSearch(e.text) end
  end)
  r:SetScript('OnEnter',function(b)
   local e=b.entry;if not (e and e.type=='item' and e.itemID and GameTooltip) then return end
   GameTooltip:SetOwner(b,'ANCHOR_RIGHT');if GameTooltip.SetItemByID then GameTooltip:SetItemByID(e.itemID) end;GameTooltip:Show()
  end)
  r:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  r.opt1:SetScript('OnClick',function()
   local e=r.entry;if not e then return end
   if e.type=='list' then self:OpenShoppingList(e.name)
   elseif e.type=='item' then self:RemoveWatch(e.key)
   elseif e.type=='term' then self:RemoveShopTerm(e.list,e.text)
   elseif e.type=='recent' then self:DeleteRecentSearch(e.text) end
  end)
  r.opt2:SetScript('OnClick',function()
   local e=r.entry;if not e then return end
   if e.type=='list' then
    self:AskShopText('Rename list "'..e.name..'" to:',e.name,function(new) self:RenameShoppingList(e.name,new) end)
   elseif e.type=='recent' then self:ShopCopyRecent(e.text) end
  end)
  r.opt3:SetScript('OnClick',function()
   local e=r.entry;if not (e and e.type=='list') then return end
   self:AskShopConfirm('Delete the shopping list "'..e.name..'"?',function() self:DeleteShoppingList(e.name) end)
  end)
  s.leftRows[i]=r
 end
 left:EnableMouseWheel(true)
 left:SetScript('OnMouseWheel',function(_,d) self.shopLeftOffset=math.max(0,(self.shopLeftOffset or 0)-(d>0 and 3 or -3));self:RefreshUI() end)
 s.newList=button(s,'New List',0,-524,96,function() self:NewShoppingList() end)
 s.import=button(s,'Import',100,-524,92,function()
  self:ShowTransferWindow();if self.transferStatus then self.transferStatus:SetText('Paste a shopping export, then click IMPORT SHOPPING.') end
 end)
 s.export=button(s,'Export',196,-524,94,function()
  self:ShowTransferWindow()
  local raw,err=self:ExportShoppingTransfer()
  if raw and self.transferEdit then self.transferEdit:SetText(raw);self.transferEdit:SetFocus();self.transferEdit:HighlightText() end
  if self.transferStatus then self.transferStatus:SetText(raw and 'Shopping lists ready; Ctrl+C to copy' or (err or 'Shopping export failed')) end
 end)
 -- Right: sortable results
 local res=self.panel(s,302,-40,702,476);s.results=res
 s.headers={}
 local cols={{'price','Price',10,150},{'name','Name',162,246},{'available','Available',576,110},{'deal','Vs Avg',466,106},{'level','Lvl',410,54}}
 for i,c in ipairs(cols) do
  local h=CreateFrame('Button',nil,res);h:SetPoint('TOPLEFT',c[3],-8);h:SetSize(c[4],20);h.field=c[1]
  h.text=label(h,c[2],4,-4,c[4]-20,'GameFontNormal')
  h.arrow=h:CreateTexture(nil,'ARTWORK');h.arrow:SetSize(12,12);h.arrow:SetPoint('LEFT',h,'LEFT',c[4]-22,0)
  h.arrow:SetTexture('Interface\\Buttons\\UI-SortArrow')
  h:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  h:SetScript('OnClick',function(b) self:ShopSortBy(b.field) end)
  s.headers[i]=h
 end
 s.rows={}
 for i=1,ROWS do
  local r=CreateFrame('Button',nil,res);r:SetPoint('TOPLEFT',6,-32-(i-1)*ROW_H);r:SetSize(686,ROW_H-1)
  if r.RegisterForClicks then r:RegisterForClicks('LeftButtonUp','RightButtonUp') end
  r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  r.sel=r:CreateTexture(nil,'BACKGROUND');r.sel:SetAllPoints();r.sel:SetColorTexture(.32,.15,.5,.45)
  r.icon=r:CreateTexture(nil,'ARTWORK');r.icon:SetSize(18,18);r.icon:SetPoint('LEFT',160,0)
  r.c={label(r,'',8,-5,146,'GameFontHighlight'),label(r,'',182,-5,222,'GameFontHighlight'),label(r,'',574,-5,104,'GameFontHighlight'),label(r,'',464,-5,100,'GameFontHighlight'),label(r,'',408,-5,50,'GameFontHighlight')}
  r:SetScript('OnClick',function(b,mouse) self:ShopRowClicked(b.data,mouse) end)
  r:SetScript('OnEnter',function(b) self:ShowRowTooltip(b) end)
  r:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  s.rows[i]=r
 end
 s.scrollTrack=res:CreateTexture(nil,'ARTWORK');s.scrollTrack:SetPoint('TOPRIGHT',-4,-32);s.scrollTrack:SetSize(4,ROWS*ROW_H)
 s.scrollTrack:SetColorTexture(.2,.12,.3,.6)
 s.scrollThumb=res:CreateTexture(nil,'OVERLAY');s.scrollThumb:SetSize(4,40);s.scrollThumb:SetColorTexture(.66,.4,.95,.9)
 res:EnableMouseWheel(true)
 res:SetScript('OnMouseWheel',function(_,d) self.shopScroll=math.max(0,(self.shopScroll or 0)-(d>0 and 3 or -3));self:RefreshUI() end)
 s.empty=label(res,'',14,-200,670,'GameFontHighlight');s.empty:SetJustifyH('CENTER')
 s.status=label(s,'',302,-530,430,'GameFontHighlightSmall')
 s.flipLedger=button(s,'Flip Ledger',742,-524,126,function() self:ShowFlipLedger() end)
 s.exportResults=button(s,'Export Results',874,-524,130,function() self:ShowShopExport() end)
 if self.InitSnipeControls then self:InitSnipeControls(s) end
 self.shopLeft='lists'
 self:InitializeShopBuyView(s)
end

local function sourceText(o)
 if o.status=='LIVE BROWSE' or o.status=='LIVE' or o.status=='NONE' then return 'Live' end
 if o.status=='SYNCED' or o.status=='SYNC STALE' then return 'Bank' end
 return 'Scan'
end
M.ShopSourceText=sourceText

local function renderLeft(self,s)
 local recent=self.shopLeft=='recent'
 s.tabLists:SetSelected(not recent);s.tabRecent:SetSelected(recent)
 local entries={}
 if recent then for _,t in ipairs(self.db.recentSearches) do entries[#entries+1]={type='recent',text=t} end
 else entries=self:ShopTreeRows() end
 local off=math.max(0,math.min(self.shopLeftOffset or 0,#entries-LEFT_ROWS));self.shopLeftOffset=off
 for i,r in ipairs(s.leftRows) do
  local e=entries[i+off];r.entry=e;r.value=e and (e.name or e.text) or nil;r:SetShown(e~=nil)
  r.opt1:Hide();r.opt2:Hide();r.opt3:Hide();r.sel:Hide()
  if e then
   r.text:ClearAllPoints()
   if e.type=='list' then
    local open=self.shopExpanded==e.name
    r.text:SetPoint('TOPLEFT',8,-4)
    r.text:SetText('|T'..(open and ICON.minus or ICON.plus)..':12:12|t  '..PURPLE..e.name..'|r')
    r.sel:SetShown(open)
    r.opt1.icon:SetTexture(ICON.search);r.opt1.tip='Search all';r.opt1:Show()
    if e.name~='Shopping' then
     r.opt2.icon:SetTexture(ICON.rename);r.opt2.tip='Rename';r.opt2:Show()
     r.opt3.icon:SetTexture(ICON.delete);r.opt3.tip='Delete';r.opt3:Show()
    end
   elseif e.type=='item' then
    r.text:SetPoint('TOPLEFT',30,-4);r.text:SetText(e.name)
    r.sel:SetShown(self.shoppingListMode and self.shopOnlyKey==e.key)
    r.opt1.icon:SetTexture(ICON.delete);r.opt1.tip='Remove from list';r.opt1:Show()
   elseif e.type=='term' then
    r.sel:SetShown(self.shoppingListMode and self.shopOnlyTerm==e.text)
    r.text:SetPoint('TOPLEFT',30,-4);r.text:SetText('|T'..ICON.search..':12:12|t '..PURPLE..e.text..'|r')
    r.opt1.icon:SetTexture(ICON.delete);r.opt1.tip='Remove search term';r.opt1:Show()
   elseif e.type=='recent' then
    r.text:SetPoint('TOPLEFT',8,-4);r.text:SetText(e.text)
    r.sel:SetShown(not self.shoppingListMode and (self.db.settings.filter or '')==e.text)
    r.opt1.icon:SetTexture(ICON.delete);r.opt1.tip='Delete';r.opt1:Show()
    r.opt2.icon:SetTexture(ICON.copy);r.opt2.tip='Copy to the open list';r.opt2:Show()
   else
    r.text:SetPoint('TOPLEFT',30,-4);r.text:SetText(DIM..'Empty|r')
   end
  end
 end
end

function M:RenderShopScreen()
 local s=self.shopScreen;if not s then return end
 s:Show()
 renderLeft(self,s)
 local searching=self:ShopSearching()
 s.searchButton:SetText(searching and 'Cancel' or 'Search')
 local typed=self.shopSearch and self.shopSearch:GetText();typed=type(typed)=='string' and not typed:match('^%s*$')
 local canAdd=self.shopExpanded~=nil and (self.selectedRow~=nil or self.shopBuy~=nil or typed or (not self.shoppingListMode and #(self.browseRows or {})==1))
 s.addButton:SetEnabled(canAdd and true or false)
 if s.snipeButton and self.SnipeHitCount then
  local on=self.snipe and self.snipe.on
  s.snipeButton:SetText(on and 'Stop Snipe' or 'Snipe');s.snipeButton:SetEnabled((on or self.ahOpen) and true or false)
  local n=self:SnipeHitCount();s.snipeHits:SetText(n>0 and ('|cff40ff40Hits ('..n..')|r') or 'Hits')
 end
 -- Buy view replaces the results (Auctionator-style)
 local buying=self.shopBuy~=nil
 s.results:SetShown(not buying);s.exportResults:SetShown(not buying);s.status:SetShown(not buying)
 if s.flipLedger then s.flipLedger:SetShown(not buying) end
 if self.RenderSnipeControls then self:RenderSnipeControls(s,buying) end
 if buying then s.buyView:Show();return self:RenderShopBuy() end
 s.buyView:Hide()
 local lo,hi=self:ShopLevelRange()
 for e,v in pairs({[s.minLevel]=lo,[s.maxLevel]=hi}) do
  if not (e.HasFocus and e:HasFocus()) then e:SetText(v and tostring(v) or '') end
 end
 if self.shopSearch and not (self.shopSearch.HasFocus and self.shopSearch:HasFocus()) and not self.shoppingListMode then
  self.shopSearch:SetText(self.db.settings.filter or '')
 end
 local sort=self.shopSort or {field='price',dir=1}
 for _,h in ipairs(s.headers) do
  h.arrow:SetShown(h.field==sort.field)
  if h.arrow.SetTexCoord then if sort.dir>0 then h.arrow:SetTexCoord(0,1,1,0) else h.arrow:SetTexCoord(0,1,0,1) end end
 end
 local source=self:ShopVisibleRows()
 local maxOff=math.max(0,#source-ROWS);local off=math.min(self.shopScroll or 0,maxOff);self.shopScroll=off
 for i,r in ipairs(s.rows) do
  local o=source[off+i];r.data=o;r:SetShown(o~=nil)
  if o then
   r.sel:SetShown(self.selectedRow==o or (self.selectedRow and self.selectedRow.marketKey==o.marketKey))
   r.icon:SetTexture(self:RowItemIcon(o,o.itemID) or 'Interface\\Icons\\INV_Misc_QuestionMark')
   local price=o.floor and o.floor>0 and self:Coins(o.floor) or (o.status=='NONE' and DIM..'None listed|r' or DIM..'Unknown|r')
   if type(o.name)~='string' or o.name=='' or o.name:match('^Item %d+$') then o.name=self:ItemName(o.itemID) or ((type(o.name)=='string' and o.name~='') and o.name) or ('Item '..tostring(o.itemID)) end
   r.c[1]:SetText(price);r.c[2]:SetText(o.name or '?')
   r.c[3]:SetText(o.quantity and tostring(o.quantity) or '--')
   r.c[4]:SetText(self:DealText(o))
   local lv=self:RowLevel(o,true);r.c[5]:SetText(lv and tostring(lv) or '|cff8f8f8f--|r')
  end
 end
 -- Scroll thumb
 if #source>ROWS then
  local track=ROWS*ROW_H;local h=math.max(20,track*ROWS/#source)
  s.scrollThumb:ClearAllPoints();s.scrollThumb:SetPoint('TOPRIGHT',s.results,'TOPRIGHT',-4,-32-(track-h)*(off/maxOff))
  s.scrollThumb:SetHeight(h);s.scrollThumb:Show();s.scrollTrack:Show()
 else s.scrollThumb:Hide();s.scrollTrack:Hide() end
 local empty=''
 if #source==0 then
  local f=self.db.settings.filter or ''
  if self.snipeView and self.SnipeEmptyText then self.shoppingSearchStatus=self:SnipeEmptyText() end
  empty=self.shoppingSearchStatus or (self.shoppingListMode and (self.shopOnlyKey~=nil and 'No price for this item yet. Open the Auction House and click it again.'
    or 'This list is empty. Add an item, or type a search term like "of the Monkey" and click Add to List.'))
   or (f~='' and ('No saved prices match "'..f..'".'..(self.ahOpen and ' Press Search to check the Auction House.' or ' Open the Auction House to search it live.')))
   or 'Type an item name and press Enter, or open a shopping list on the left.'
 end
 s.empty:SetText(empty);s.empty:SetShown(empty~='')
 local status=(self.snipeView and self.SnipeStatus and self:SnipeStatus()) or (self.ListSearchStatus and self:ListSearchStatus()) or (self.TermSearchStatus and self:TermSearchStatus())
 if not status and #source>0 then
  status=#source..' result'..(#source==1 and '' or 's')
  if self.shoppingListMode then status=status..'  |  List: '..(self.activeList or 'Shopping') end
  status=status..'  |  Green Vs Avg = '..self:DealPercent()..'% of average or less'
  local lv=self:LevelRangeText();if lv then status=status..'  |  '..lv end
  if self.shoppingListMode and self:FlipMaxBuy() then status=status..'  |  Terms: max '..self:Coins(self:FlipMaxBuy()) end
  local f=self.shopFilters
  if f and not self.shoppingListMode then
   local bits={}
   if f.exact then bits[#bits+1]='exact name' end
   if f.maxPrice then bits[#bits+1]='max '..self:Coins(f.maxPrice) end
   if f.minQuantity then bits[#bits+1]='min '..f.minQuantity..' available' end
   status=status..'  |  Filters: '..table.concat(bits,', ')
  end
 end
 s.status:SetText(status or '')
 s.exportResults:SetEnabled(#source>0)
end
