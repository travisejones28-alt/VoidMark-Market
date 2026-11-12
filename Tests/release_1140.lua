return function(M,check,jobs,advance,emit)
-- 1.14.0 Flipping: search terms in shopping lists and the Vs Avg deal column.
local function click(f,mouse) f.scripts.OnClick(f,mouse or 'LeftButton') end
local function fresh()
 M.shopExpanded=nil;M.shopOnlyKey=nil;M.shopFilters=nil;M.shopSort=nil;M.shopScroll=0;M.shopLeftOffset=0
 M.listSearch=nil;M.termSearch=nil;M.termRows=nil;M.shoppingSearchStatus=nil;M.selectedRow=nil;M.shopBuy=nil
 M.browseRows={};M.shoppingListMode=false;M.db.settings.filter='';M.shopLeft='lists';M.db.shopTerms=nil
 if M.shopSearch then M.shopSearch:SetText('') end
end
local function history(key,id,suffix,name,medians)
 local h={};for i,v in ipairs(medians) do h[i]={at=time()-i*3600,median=v} end
 M.db.market[key]={itemID=id,itemSuffix=suffix,marketKey=key,name=name,latest={},history=h}
end

check('1.14 Search terms: add, dedupe, limit, remove; shown under the open list',function()
 fresh();M:SetView('browse');M.ahOpen=false
 M:SetList('Flips');M.shopExpanded='Flips'
 assert(M:AddShopTerm('Flips','  of the Monkey '))
 local ok,why=M:AddShopTerm('Flips','OF THE MONKEY');assert(not ok and why:find('already'),'dedupe')
 assert(not M:AddShopTerm('Flips','x'),'too short')
 assert(M:AddShopTerm('Flips','of the Tiger') and table.concat(M:ShopTerms('Flips'),',')=='of the Monkey,of the Tiger')
 M:RenderUI();local s=M.shopScreen
 local terms={};for _,r in ipairs(s.leftRows) do if r:IsShown() and r.entry and r.entry.type=='term' then terms[#terms+1]=r end end
 assert(#terms==2 and terms[1].opt1:IsShown(),'term rows with remove button')
 -- Clicking a term runs a normal name search for it.
 M.ahOpen=true;local searched;local old=M.SearchShopTerms;M.SearchShopTerms=function(_,l,t) searched=l..'/'..tostring(t) end
 click(terms[1]);M.SearchShopTerms=old;M.ahOpen=false
 assert(searched=='Flips/of the Monkey' and M.shopOnlyTerm=='of the Monkey' and M.shoppingListMode,'term click sweeps only that term')
 click(terms[2].opt1);assert(table.concat(M:ShopTerms('Flips'),',')=='of the Monkey','remove term')
 for i=1,40 do M:AddShopTerm('Flips','term '..i) end
 assert(#M:ShopTerms('Flips')==30,'30 terms per list')
 M.db.shopTerms=nil
end)

check('1.14 Add to List with typed text and no selection adds a search term',function()
 fresh();M:SetView('browse');M.ahOpen=false
 M:SetList('Flips');M.shopExpanded='Flips';M:RenderUI();local s=M.shopScreen
 -- Typed and searched (Enter): the box keeps the text after the search.
 M.db.settings.filter='of the Bear';M.shopSearch:SetText('of the Bear');M:RenderUI()
 assert(s.addButton.enabled,'Add to List enabled by typed text')
 click(s.addButton);assert(M:ShopTerms('Flips')[1]=='of the Bear','term added: '..tostring(M:ShopTerms('Flips')[1]));assert(not next(M:ListBook('Flips')),'no item: '..tostring(next(M:ListBook('Flips'))))
 -- A selected result still adds the item itself.
 M.selectedRow={marketKey=61,name='Linen'};click(s.addButton);assert(M:ListBook('Flips')[61],'item added')
 M:RemoveWatch(61);M.db.shopTerms=nil
end)

check('1.14 Rename moves search terms; delete removes them',function()
 fresh();M:SetView('browse');M.ahOpen=false
 M:SetList('Old');M:AddShopTerm('Old','of the Owl')
 assert(M:RenameShoppingList('Old','New') and M:ShopTerms('New')[1]=='of the Owl' and #M:ShopTerms('Old')==0)
 assert(M:DeleteShoppingList('New') and #M:ShopTerms('New')==0)
end)

check('1.14 Import accepts an Auctionator list export as search terms',function()
 fresh()
 local ok,msg=M:ImportShoppingTransfer('Greens Flip^of the Monkey^"of the Tiger"^of the Bear;;10;30\r\n')
 assert(ok and msg:find('3 search terms',1,true),tostring(msg))
 assert(table.concat(M:ShopTerms('Greens Flip'),',')=='of the Monkey,of the Tiger,of the Bear')
 local bad=M:ImportShoppingTransfer('just text');assert(not bad,'plain text is still rejected')
 M:DeleteShoppingList('Greens Flip')
end)

check('1.14 Opening a list sweeps its terms; suffix variants stay separate, lowest price kept',function()
 fresh();M:SetView('browse');M.ahOpen=true;M.queue.nextSend=0
 local A=C_AuctionHouse;local origGet,origSend=A.GetBrowseResults,A.SendBrowseQuery
 local last
 A.SendBrowseQuery=function(q) last=q.searchString end
 A.GetBrowseResults=function()
  if last=='of the Monkey' then return {
   {itemKey={itemID=500,itemSuffix=-10,itemLevel=0},minPrice=900,totalQuantity=1},
   {itemKey={itemID=500,itemSuffix=-11,itemLevel=0},minPrice=4000,totalQuantity=2}} end
  return {{itemKey={itemID=500,itemSuffix=-10,itemLevel=0},minPrice=700,totalQuantity=1}}
 end
 local ok,err=pcall(function()
  M:SetList('Flips');M:AddShopTerm('Flips','of the Monkey');M:AddShopTerm('Flips','Bandit')
  M:OpenShoppingList('Flips')
  assert(M:ShopSearching() and M.termSearch.total==2,'two term searches queued')
  for _=1,2 do M.queue.nextSend=0;M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED') end
  assert(M.termSearch.finished and not M:ShopSearching(),'sweep finished')
  local rows=M:ShoppingResultRows()
  assert(#rows==2,'two variants, got '..#rows)
  local byKey={};for _,r in ipairs(rows) do byKey[r.marketKey]=r end
  assert(byKey[M:Key(500,-10)].floor==700,'lowest of both terms kept')
  assert(byKey[M:Key(500,-11)].floor==4000,'other suffix separate')
  assert(M.db.liveSeen[M:Key(500,-10)],'live price recorded')
 end)
 A.GetBrowseResults,A.SendBrowseQuery=origGet,origSend;M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
 M:DeleteShoppingList('Flips');assert(ok,err)
end)

check('1.14 Cancel stops a term sweep and clears its queued searches',function()
 fresh();M:SetView('browse');M.ahOpen=true
 local oldPump=M.PumpQueue;M.PumpQueue=function() end
 local origGet=C_AuctionHouse.GetBrowseResults;C_AuctionHouse.GetBrowseResults=function() return {} end
 local ok,err=pcall(function()
  M:SetList('Flips');M:AddShopTerm('Flips','of the Eagle');M:AddShopTerm('Flips','of the Whale')
  M:OpenShoppingList('Flips');assert(M:ShopSearching(),'searching: terms='..#M:ShopTerms('Flips')..' run='..tostring(M.termSearch and M.termSearch.total)..' fin='..tostring(M.termSearch and M.termSearch.finished)..' waiting='..#M.queue.waiting)
  M:ShopStopSearch()
  assert(not M:ShopSearching(),'stopped')
  for _,r in ipairs(M.queue.waiting) do assert(not tostring(r.id):find('^browse%-term:'),'term request left in queue') end
 end)
 M.PumpQueue=oldPump;C_AuctionHouse.GetBrowseResults=origGet;M.queue.waiting={};M.queue.dedupe={}
 M:DeleteShoppingList('Flips');assert(ok,err)
end)

check('1.14 Armor-type terms and max buy price filter the sweep; starter list goes on the main list',function()
 fresh();M:SetView('browse');M.ahOpen=true;M.queue.nextSend=0
 assert(select(2,M:ParseShopTerm('Leather: of the Monkey'))==2 and M:ParseShopTerm('leather: of the Monkey')=='of the Monkey')
 assert(select(2,M:ParseShopTerm('of the Monkey'))==nil and select(2,M:ParseShopTerm('wood: of x'))==nil)
 local A=C_AuctionHouse;local origGet,origSend=A.GetBrowseResults,A.SendBrowseQuery
 local origInfo=GetItemInfoInstant;local sent
 GetItemInfoInstant=function(id) if id==700 then return id,'Armor','Leather','INV_FEET',0,4,2 elseif id==701 then return id,'Armor','Cloth','INV_FEET',0,4,1 end end
 A.SendBrowseQuery=function(q) sent=q.searchString end
 A.GetBrowseResults=function() return {
  {itemKey={itemID=700,itemSuffix=-10,itemLevel=0},minPrice=1200,totalQuantity=1},
  {itemKey={itemID=701,itemSuffix=-10,itemLevel=0},minPrice=900,totalQuantity=1},
  {itemKey={itemID=702,itemSuffix=-10,itemLevel=0},minPrice=800,totalQuantity=1},  -- not cached: kept
  {itemKey={itemID=700,itemSuffix=-11,itemLevel=0},minPrice=50000,totalQuantity=1}} end
 local ok,err=pcall(function()
  M:SetList('Flips');M:AddShopTerm('Flips','leather: of the Monkey')
  M.db.settings.flipMaxBuy=1500
  M:OpenShoppingList('Flips');M.queue.nextSend=0;M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  assert(sent=='of the Monkey','prefix stripped before searching')
  local ids={};for _,r in ipairs(M:ShoppingResultRows()) do ids[#ids+1]=r.itemID..':'..r.floor end;table.sort(ids)
  assert(table.concat(ids,',')=='700:1200,702:800','cloth and over-max dropped: '..table.concat(ids,','))
 end)
 A.GetBrowseResults,A.SendBrowseQuery,GetItemInfoInstant=origGet,origSend,origInfo
 M.db.settings.flipMaxBuy=0;M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
 M:DeleteShoppingList('Flips');assert(ok,err)
 SlashCmdList.VOIDMARKMARKET('flipmax 15');assert(M:FlipMaxBuy()==1500,'15 silver')
 SlashCmdList.VOIDMARKMARKET('flipmax 0');assert(M:FlipMaxBuy()==nil,'off')
 SlashCmdList.VOIDMARKMARKET('flipstarter');assert(#M:ShopTerms('Shopping')==#M.FLIP_STARTER)
 assert(M:AddFlipStarter()==0,'no duplicates on a second run')
 M.db.shopTerms=nil
end)

check('1.14 Level range limits term sweeps and name searches; boxes save it',function()
 fresh();M:SetView('browse');M.ahOpen=true;M.queue.nextSend=0
 local A=C_AuctionHouse;local origGet,origSend,origInfo=A.GetBrowseResults,A.SendBrowseQuery,GetItemInfo
 local sent={}
 A.SendBrowseQuery=function(q) sent[#sent+1]=q end
 GetItemInfo=function(id) local req=({[800]=15,[801]=25,[802]=45})[id];if req then return 'X','l',2,30,req end end
 A.GetBrowseResults=function() return {
  {itemKey={itemID=800,itemSuffix=-10,itemLevel=0},minPrice=500,totalQuantity=1},
  {itemKey={itemID=801,itemSuffix=-10,itemLevel=0},minPrice=600,totalQuantity=1},
  {itemKey={itemID=802,itemSuffix=-10,itemLevel=0},minPrice=700,totalQuantity=1},
  {itemKey={itemID=803,itemSuffix=-10,itemLevel=0},minPrice=800,totalQuantity=1}} end -- uncached: kept
 local ok,err=pcall(function()
  M:RenderUI();local s=M.shopScreen
  s.minLevel:SetText('40');s.maxLevel:SetText('20');s.minLevel.scripts.OnEnterPressed(s.minLevel)
  local lo,hi=M:ShopLevelRange();assert(lo==20 and hi==40,'saved and ordered: '..tostring(lo)..'-'..tostring(hi))
  M:SetList('Flips');M:AddShopTerm('Flips','of the Monkey')
  M:OpenShoppingList('Flips');M.queue.nextSend=0;M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  assert(sent[#sent].minLevel==20 and sent[#sent].maxLevel==40,'query carries the range')
  local ids={};for _,r in ipairs(M:ShoppingResultRows()) do ids[#ids+1]=r.itemID end;table.sort(ids)
  assert(table.concat(ids,',')=='801,803','level filter: '..table.concat(ids,','))
  M:RenderUI();assert(s.status:GetText():find('level 20-40',1,true),'status shows range')
  -- Plain name searches use it too.
  M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
  M.db.settings.filter='Monkey';M:LiveNameSearch('Monkey');M.queue.nextSend=0;M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');jobs()
  assert(sent[#sent].minLevel==20 and #M.browseRows==2,'name search filtered: '..#M.browseRows)
  -- Blank boxes clear it.
  s.minLevel:SetText('');s.maxLevel:SetText('');s.maxLevel.scripts.OnEditFocusLost(s.maxLevel)
  assert(M:ShopLevelRange()==nil and select(2,M:ShopLevelRange())==nil,'cleared')
 end)
 A.GetBrowseResults,A.SendBrowseQuery,GetItemInfo=origGet,origSend,origInfo
 M.db.settings.shopMinLevel=0;M.db.settings.shopMaxLevel=0
 M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
 M:DeleteShoppingList('Flips');assert(ok,err)
end)

check('1.14 Vs Avg compares against the exact suffix history and sorts deals first',function()
 fresh();M:SetView('browse');M.ahOpen=false
 local monkey,bear=M:Key(600,-10),M:Key(600,-12)
 history(monkey,600,-10,'Bandit Boots of the Monkey',{4000,4000,4000})
 history(bear,600,-12,'Bandit Boots of the Bear',{1000,1000})
 local newKey=M:Key(601,-10)
 M.browseRows={
  {marketKey=monkey,itemID=600,name='Bandit Boots of the Monkey',floor=1000,quantity=1,status='LIVE BROWSE'},
  {marketKey=bear,itemID=600,name='Bandit Boots of the Bear',floor=1500,quantity=1,status='LIVE BROWSE'},
  {marketKey=newKey,itemID=601,name='Unknown Thing of the Monkey',floor=50,quantity=1,status='LIVE BROWSE'}}
 assert(M:DealRatio(M.browseRows[1])==25,'monkey 25% of its own average')
 assert(M:DealRatio(M.browseRows[2])==150,'bear priced on bear history only')
 assert(M:DealRatio(M.browseRows[3])==nil,'no history, no verdict')
 M:RenderUI();local s=M.shopScreen
 local mrow;for _,r in ipairs(s.rows) do if r:IsShown() and r.data.marketKey==monkey then mrow=r end end
 local t1=mrow.c[4]:GetText();assert(t1:find('25%',1,true) and t1:find('40ff40',1,true),'green deal: '..t1)
 -- Header 4 sorts by Vs Avg: deals first, unknown last.
 click(s.headers[4]);M:RenderUI()
 assert(s.rows[1].data.marketKey==monkey and s.rows[3].data.marketKey==newKey,'deal sort')
 -- One scan is not history.
 history(bear,600,-12,'Bandit Boots of the Bear',{1000});assert(M:DealRatio(M.browseRows[2])==nil)
 -- Threshold setting.
 M.db.settings.dealPercent=20;assert(not M:DealText(M.browseRows[1]):find('40ff40',1,true));M.db.settings.dealPercent=60
 SlashCmdList.VOIDMARKMARKET('deal 45');assert(M:DealPercent()==45);SlashCmdList.VOIDMARKMARKET('deal 5');assert(M:DealPercent()==45)
 M.db.settings.dealPercent=60
 M.db.market[monkey]=nil;M.db.market[bear]=nil
end)
end
