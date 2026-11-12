return function(M,check,jobs,advance,emit)
-- 1.13.0 Shopping tab laid out and behaving like Auctionator's Shopping tab.
local function click(f,mouse) f.scripts.OnClick(f,mouse or 'LeftButton') end
local function fresh()
 M.shopExpanded=nil;M.shopOnlyKey=nil;M.shopFilters=nil;M.shopSort=nil;M.shopScroll=0;M.shopLeftOffset=0
 M.listSearch=nil;M.shoppingSearchStatus=nil;M.selectedRow=nil;M.shopBuy=nil;M.browseRows={};M.shoppingListMode=false
 M.db.settings.filter='';M.shopLeft='lists'
end
local function results()
 local out={};for _,r in ipairs(M.shopScreen.rows) do if r:IsShown() then out[#out+1]=r.data.name end end
 return table.concat(out,',')
end

check('1.13 Shopping lists expand like folders; items search alone; right-click collapses',function()
 fresh();M:SetView('browse');M.ahOpen=true
 local searched={};local old=M.SearchShoppingList;M.SearchShoppingList=function(_,k) searched[#searched+1]=k==nil and 'ALL' or k end
 local ok,err=pcall(function()
  M:SetList('Mats');M:SetWatch(61,nil);M:SetWatch(62,nil)
  M.db.market[61]={itemID=61,marketKey=61,name='Linen',latest={}};M.db.market[62]={itemID=62,marketKey=62,name='Wool',latest={}}
  M:RenderUI();local s=M.shopScreen
  assert(not s.addButton.enabled,'Add to List needs an open list')
  -- Find the Mats header and open it: auto-searches the whole list.
  local header;for _,r in ipairs(s.leftRows) do if r:IsShown() and r.entry and r.entry.type=='list' and r.entry.name=='Mats' then header=r end end
  assert(header and header.opt1:IsShown() and header.opt2:IsShown() and header.opt3:IsShown(),'list options')
  click(header);M:RenderUI()
  assert(M.shopExpanded=='Mats' and M.shoppingListMode and searched[1]=='ALL','expand did not search the list')
  local names={};for _,r in ipairs(s.leftRows) do if r:IsShown() and r.entry and r.entry.type=='item' then names[#names+1]=r.entry.name end end
  assert(table.concat(names,',')=='Linen,Wool','items under the open list: '..table.concat(names,','))
  -- Clicking an item searches just that item and filters the results to it.
  local wool;for _,r in ipairs(s.leftRows) do if r:IsShown() and r.entry and r.entry.name=='Wool' then wool=r end end
  click(wool);M:RenderUI()
  assert(searched[2]==62 and M.shopOnlyKey==62 and results()=='Wool','single item search: '..results())
  -- Item delete icon removes it from the list.
  wool.opt1.scripts.OnClick(wool.opt1);assert(not M:ListBook('Mats')[62],'remove item')
  -- Right-click collapses.
  M:RenderUI();click(s.leftRows[1],'RightButton');assert(M.shopExpanded==nil,'right-click collapse')
  -- The main Shopping list has no rename/delete.
  M:RenderUI();assert(s.leftRows[1].value=='Shopping' and not s.leftRows[1].opt2:IsShown() and not s.leftRows[1].opt3:IsShown())
 end)
 M.SearchShoppingList=old;assert(ok,err)
end)

check('1.13 Search button: Cancel while searching, empty box searches the open list',function()
 fresh();M:SetView('browse');M.ahOpen=true
 local calls={};local old=M.SearchShoppingList;M.SearchShoppingList=function(_,k) calls[#calls+1]=k or 'ALL' end
 local ok,err=pcall(function()
  M:SetList('Mats');M.shopExpanded='Mats'
  M.shopSearch:SetText('');M:ShopSearchClicked();assert(calls[1]=='ALL','empty box should search the list')
  M.listSearch={list='Mats',total=5,done=2};M:RenderUI()
  assert(M.shopScreen.searchButton:GetText()=='Cancel','button should read Cancel')
  M:ShopSearchClicked();assert(M.listSearch==nil,'Cancel stops the search')
  M:RenderUI();assert(M.shopScreen.searchButton:GetText()=='Search')
 end)
 M.SearchShoppingList=old;assert(ok,err)
end)

check('1.13 Results sort by clicking Price / Name / Available and scroll with the wheel',function()
 fresh();M:SetView('browse');M.ahOpen=false
 M.browseRows={{marketKey=1,itemID=1,name='Bravo',floor=300,quantity=5,status='LIVE BROWSE'},
  {marketKey=2,itemID=2,name='Alpha',floor=100,quantity=50,status='LIVE BROWSE'},
  {marketKey=3,itemID=3,name='Charlie',floor=200,quantity=1,status='LIVE BROWSE'}}
 M:RenderUI();local s=M.shopScreen
 assert(results()=='Alpha,Charlie,Bravo','default price low-high: '..results())
 click(s.headers[1]);M:RenderUI();assert(results()=='Bravo,Charlie,Alpha','price high-low: '..results())
 click(s.headers[2]);M:RenderUI();assert(results()=='Alpha,Bravo,Charlie','name: '..results())
 click(s.headers[3]);M:RenderUI();assert(results()=='Charlie,Bravo,Alpha','available low-high: '..results())
 local many={};for i=1,40 do many[i]={marketKey=100+i,itemID=100+i,name=('Item%02d'):format(i),floor=i,quantity=1,status='LIVE BROWSE'} end
 M.browseRows=many;M.shopSort=nil;M:RenderUI();assert(s.rows[1].data.name=='Item01')
 s.results.scripts.OnMouseWheel(s.results,-1);M:RenderUI();assert(s.rows[1].data.name=='Item04','wheel scrolls 3')
 M.shopScroll=99;M:RenderUI();assert(s.rows[M.SHOP_RESULT_ROWS].data.name=='Item40','clamped to the end')
 assert(s.status:GetText():find('40 results',1,true))
end)

check('1.13 Result clicks: left buys, right shows history, shift puts the name in the box',function()
 fresh();M:SetView('browse');M.ahOpen=true
 M.browseRows={{marketKey=61,itemID=61,name='Linen',floor=43,quantity=120,status='LIVE BROWSE'}}
 local opened,history;local oldOpen,oldHist=M.ShopBuyOpen,M.ShowHistoryWindow
 M.ShopBuyOpen=function(_,r) opened=r end;M.ShowHistoryWindow=function(_,r) history=r end
 local oldShift=IsShiftKeyDown;local shift=false;IsShiftKeyDown=function() return shift end
 local ok,err=pcall(function()
  M:RenderUI();local r=M.shopScreen.rows[1]
  click(r,'RightButton');assert(history and history.marketKey==61 and not opened,'right-click history')
  shift=true;M.shopSearch:SetText('');click(r);assert(M.shopSearch:GetText()=='Linen' and not opened,'shift-click name');shift=false
  click(r);assert(opened and opened.marketKey==61 and M.selectedRow.marketKey==61,'left-click buy view')
 end)
 M.ShopBuyOpen,M.ShowHistoryWindow,IsShiftKeyDown=oldOpen,oldHist,oldShift;assert(ok,err)
end)

check('1.13 Recent searches: delete and copy to the open list',function()
 fresh();M:SetView('browse');M.ahOpen=false
 M.db.recentSearches={'Linen','Mystery thing'}
 M.db.market[61]={itemID=61,marketKey=61,name='Linen',latest={}}
 M:SetList('Mats');M.shopExpanded='Mats';M.shopLeft='recent';M:RenderUI();local s=M.shopScreen
 assert(s.tabRecent.text and s.leftRows[1].entry.text=='Linen' and s.leftRows[1].opt2:IsShown())
 s.leftRows[1].opt2.scripts.OnClick(s.leftRows[1].opt2);assert(M:ListBook('Mats')[61],'copy to list')
 assert(not M:ShopCopyRecent('Mystery thing'),'unknown names are not added')
 M.shopExpanded=nil;assert(not M:ShopCopyRecent('Linen'),'needs an open list')
 M:RenderUI();s.leftRows[2].opt1.scripts.OnClick(s.leftRows[2].opt1)
 assert(#M.db.recentSearches==1 and M.db.recentSearches[1]=='Linen','delete recent')
end)

check('1.13 Lists: rename keeps items, delete removes, the main list is protected',function()
 fresh();M:SetView('browse');M.ahOpen=false
 M:SetList('Old');M:SetWatch(61,nil);M:SetWatch(62,nil)
 assert(M:RenameShoppingList('Old','New'))
 assert(not M.db.shoppingLists.Old and M:ListBook('New')[61] and M:ListBook('New')[62] and M.shopExpanded=='New','rename moved items')
 assert(M:DeleteShoppingList('New') and not M.db.shoppingLists.New and M.shopExpanded==nil,'delete list')
 assert(not M:DeleteShoppingList('Shopping') and M:ListBook('Shopping'),'main list protected')
 assert(not M:RenameShoppingList('Shopping','X'),'main list rename blocked')
 -- New List prompt creates and opens the list.
 local oldShow,oldDialogs=StaticPopup_Show,StaticPopupDialogs;local shown
 StaticPopupDialogs=StaticPopupDialogs or {};StaticPopup_Show=function(_,_,_,data) shown=data end
 M:NewShoppingList();shown.accept('  Herbs  ')
 StaticPopup_Show,StaticPopupDialogs=oldShow,oldDialogs
 assert(M.db.shoppingLists.Herbs and M.shopExpanded=='Herbs','new list')
end)

check('1.13 More... filters (exact name, max price, min available) and CSV export',function()
 fresh();M:SetView('browse');M.ahOpen=false
 M.browseRows={{marketKey=1,itemID=1,name='Linen Cloth',floor=500,quantity=10,status='LIVE BROWSE'},
  {marketKey=2,itemID=2,name='Bolt of Linen Cloth',floor=2000,quantity=3,status='LIVE BROWSE'},
  {marketKey=3,itemID=3,name='Linen Cloth "Rare"',floor=90000,quantity=40,status='LIVE BROWSE'}}
 M.db.settings.filter='Linen Cloth'
 M.shopFilters={exact=true};assert(results()=='' or true);M:RenderUI();assert(results()=='Linen Cloth','exact: '..results())
 M.shopFilters={maxPrice=2000};M:RenderUI();assert(results()=='Linen Cloth,Bolt of Linen Cloth','max price: '..results())
 M.shopFilters={minQuantity=5};M:RenderUI();assert(results()=='Linen Cloth,Linen Cloth "Rare"','min qty: '..results())
 assert(M.shopScreen.status:GetText():find('Filters',1,true))
 M.shopFilters=nil;local csv=M:ShopResultsCSV()
 assert(csv:find('^Price,Name,Available\n500,"Linen Cloth",10\n2000,"Bolt of Linen Cloth",3\n',1) and csv:find('"Linen Cloth ""Rare"""',1,true),csv)
 -- A plain Search clears More... filters.
 M.shopFilters={exact=true};local old=M.LiveNameSearch;M.LiveNameSearch=function() end
 M:ShopSearch('Wool');M.LiveNameSearch=old;assert(M.shopFilters==nil)
end)

check('1.13 Searching one list entry only queues that item',function()
 fresh();M:SetView('browse');M.ahOpen=true
 M:SetList('Mats');M:SetWatch(61,nil);M:SetWatch(62,nil)
 local asked={};local oldSearch,oldCan=M.Search,M.CanUseAuctionHouse
 M.Search=function(_,m) asked[#asked+1]=m.marketKey;return true end;M.CanUseAuctionHouse=function() return true end
 local ok,err=pcall(function()
  assert(M:SearchShoppingList(62));assert(#asked==1 and asked[1]==62,'only the clicked item')
  asked={};assert(M:SearchShoppingList());assert(#asked==2,'whole list')
 end)
 M.Search,M.CanUseAuctionHouse=oldSearch,oldCan;M.listSearch=nil;assert(ok,err)
end)
end
