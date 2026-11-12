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

check('1.14.2 Term options: per-term max price and level, armor slot, category-only terms',function()
 fresh()
 assert(M:ParseMoneyText('75s')==7500 and M:ParseMoneyText('1g25s')==12500 and M:ParseMoneyText('50')==5000 and M:ParseMoneyText('x')==nil)
 local t,a,sp=M:ParseShopTerm('leather: agility max 50s')
 assert(t=='agility' and a==2 and sp.max==5000,'agility max')
 t,a,sp=M:ParseShopTerm('cloth: intellect lvl 15+');assert(t=='intellect' and a==1 and sp.minLevel==15 and not sp.maxLevel)
 t,a,sp=M:ParseShopTerm('mail head: max 75s');assert(t=='' and a==3 and sp.slot[1]=='INVTYPE_HEAD' and sp.max==7500)
 t,a,sp=M:ParseShopTerm('Leather Chest: lvl 30-20');assert(sp.minLevel==20 and sp.maxLevel==30 and #sp.slot==2)
 t,a=M:ParseShopTerm('Robe: of x');assert(t=='Robe: of x' and a==nil,'unknown prefix is plain text')
 assert(not M:AddShopTerm('Flips','head: max 75s'),'no text and no armor is refused')
 -- Sweep: category search for helms, slot + per-term max applied, per-term level beats the boxes.
 M:SetView('browse');M.ahOpen=true;M.queue.nextSend=0
 local A=C_AuctionHouse;local origGet,origSend,origInst,origInfo=A.GetBrowseResults,A.SendBrowseQuery,GetItemInfoInstant,GetItemInfo
 local sent
 A.SendBrowseQuery=function(q) sent=q end
 GetItemInfoInstant=function(id) local r=({[900]={'INVTYPE_HEAD',3},[901]={'INVTYPE_CHEST',3},[902]={'INVTYPE_HEAD',2}})[id]
  if r then return id,'Armor','x',r[1],0,4,r[2] end end
 GetItemInfo=function(id) return 'X','l',2,30,30 end
 A.GetBrowseResults=function() return {
  {itemKey={itemID=900,itemSuffix=0,itemLevel=0},minPrice=7000,totalQuantity=1},
  {itemKey={itemID=900,itemSuffix=-12,itemLevel=0},minPrice=9000,totalQuantity=1}, -- over 75s
  {itemKey={itemID=901,itemSuffix=0,itemLevel=0},minPrice=100,totalQuantity=1},   -- chest
  {itemKey={itemID=902,itemSuffix=0,itemLevel=0},minPrice=100,totalQuantity=1}} end -- leather
 local ok,err=pcall(function()
  M.db.settings.flipMaxBuy=200 -- global max is overridden by the term's own max
  M.db.settings.shopMinLevel=40;M.db.settings.shopMaxLevel=50 -- boxes would exclude level 30
  M:SetList('Flips');assert(M:AddShopTerm('Flips','mail head: max 75s lvl 20-35'))
  M:OpenShoppingList('Flips');M.queue.nextSend=0;M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  assert(sent.searchString=='' and sent.itemClassFilters[1].classID==4 and sent.itemClassFilters[1].subClassID==3
   and sent.itemClassFilters[1].inventoryType==1,'category query')
  assert(sent.minLevel==20 and sent.maxLevel==35,'term level used')
  local rows=M:ShoppingResultRows();assert(#rows==1 and rows[1].floor==7000,'only the mail helm under 75s: '..#rows)
 end)
 A.GetBrowseResults,A.SendBrowseQuery,GetItemInfoInstant,GetItemInfo=origGet,origSend,origInst,origInfo
 M.db.settings.flipMaxBuy=0;M.db.settings.shopMinLevel=0;M.db.settings.shopMaxLevel=0
 M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
 M:DeleteShoppingList('Flips');assert(ok,err)
 -- flipstarter swaps the old 1.14.0 terms for the new list.
 M.db.shopTerms=nil;for _,o in ipairs(M.OLD_FLIP_STARTER) do M:AddShopTerm('Shopping',o) end;M:AddShopTerm('Shopping','my own term')
 M:AddFlipStarter();local terms=M:ShopTerms('Shopping')
 assert(#terms==#M.FLIP_STARTER+1 and terms[1]=='my own term','old starter replaced, own terms kept')
 M.db.shopTerms=nil
end)

check('1.14.3 Term sweeps and name searches read every page of results, not just the first',function()
 fresh();M:SetView('browse');M.ahOpen=true;M.queue.nextSend=0
 local A=C_AuctionHouse;local o={A.GetBrowseResults,A.SendBrowseQuery,A.HasFullBrowseResults,A.RequestMoreBrowseResults}
 local page,more=1,0
 local p1={{itemKey={itemID=950,itemSuffix=-10,itemLevel=0},minPrice=300,totalQuantity=1}}
 local p2={{itemKey={itemID=951,itemSuffix=-10,itemLevel=0},minPrice=900,totalQuantity=1}}  -- level 30 item, page 2
 A.SendBrowseQuery=function() page=1 end
 A.RequestMoreBrowseResults=function() more=more+1;page=page+1 end
 A.HasFullBrowseResults=function() return page>=2 end
 A.GetBrowseResults=function() local r={unpack(p1)};if page>=2 then r[2]=p2[1] end;return r end
 local function pump(event) M.queue.nextSend=0;M:PumpQueue();emit(event) end
 local ok,err=pcall(function()
  M:SetList('Flips');M:AddShopTerm('Flips','of the Monkey');M:AddShopTerm('Flips','of the Tiger')
  M:OpenShoppingList('Flips')
  pump('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')               -- page 1 of Monkey
  assert(M:ShopSearching() and M.queue.waiting[1].kind=='browsemore','page 2 queued ahead of the next term')
  pump('AUCTION_HOUSE_BROWSE_RESULTS_ADDED')                 -- page 2 of Monkey
  pump('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');pump('AUCTION_HOUSE_BROWSE_RESULTS_ADDED') -- Tiger
  assert(more==2 and M.termSearch.finished,'both terms paged and finished')
  local ids={};for _,r in ipairs(M:ShoppingResultRows()) do ids[#ids+1]=r.itemID end;table.sort(ids)
  assert(table.concat(ids,',')=='950,951','page 2 item found: '..table.concat(ids,','))
  -- Name search pages too.
  M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
  M.db.settings.filter='Monkey';M:LiveNameSearch('Monkey');pump('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED');jobs()
  assert(#M.browseRows==1 and M:ShopSearching(),'still searching page 2')
  pump('AUCTION_HOUSE_BROWSE_RESULTS_ADDED');jobs()
  assert(#M.browseRows==2 and not M:ShopSearching(),'name search has both pages')
  -- Page cap.
  A.HasFullBrowseResults=function() return false end
  assert(M:BrowseNeedsMore(1) and not M:BrowseNeedsMore(M.BROWSE_MAX_PAGES),'page cap')
 end)
 A.GetBrowseResults,A.SendBrowseQuery,A.HasFullBrowseResults,A.RequestMoreBrowseResults=o[1],o[2],o[3],o[4]
 M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
 M:DeleteShoppingList('Flips');assert(ok,err)
end)

check('1.14.4 Results show the required level and sort by it',function()
 fresh();M:SetView('browse');M.ahOpen=false
 local orig=GetItemInfo
 GetItemInfo=function(id) local req=({[960]=32,[961]=18})[id];if req then return 'X','l',2,30,req end end
 local ok,err=pcall(function()
  M.browseRows={{marketKey=960,itemID=960,name='High',floor=100,quantity=1,status='LIVE BROWSE'},
   {marketKey=961,itemID=961,name='Low',floor=200,quantity=1,status='LIVE BROWSE'},
   {marketKey=962,itemID=962,name='Unloaded',floor=300,quantity=1,status='LIVE BROWSE'}}
  M:RenderUI();local s=M.shopScreen
  assert(s.headers[5].text:GetText()=='Lvl','header')
  assert(s.rows[1].c[5]:GetText()=='32' and s.rows[2].c[5]:GetText()=='18' and s.rows[3].c[5]:GetText():find('--',1,true),'levels')
  s.headers[5].scripts.OnClick(s.headers[5]);M:RenderUI()
  assert(s.rows[1].data.name=='Low' and s.rows[2].data.name=='High' and s.rows[3].data.name=='Unloaded','level sort, unknown last')
 end)
 GetItemInfo=orig;assert(ok,err)
end)

check('1.14.5 Tooltips show the exact suffix (link, then item key) and sit below the buy-view icon',function()
 local calls={}
 local tip={SetHyperlink=function(_,l) calls[#calls+1]='link:'..l end,
  SetItemKey=function(_,id,lvl,suf) calls[#calls+1]='key:'..id..':'..lvl..':'..suf end,
  SetItemByID=function(_,id) calls[#calls+1]='id:'..id end}
 assert(M:SetVariantTooltip(tip,M:Key(70,-5),70,'|Hitem:70|h')=='link' and calls[1]=='link:|Hitem:70|h')
 assert(M:SetVariantTooltip(tip,M:Key(70,-5),70)=='key' and calls[2]=='key:70:0:-5','suffix via item key')
 assert(M:SetVariantTooltip(tip,70,70)=='base' and calls[3]=='id:70','plain item by ID')
 tip.SetItemKey=nil;assert(M:SetVariantTooltip(tip,M:Key(70,-5),70)=='base','older client falls back')
 -- Buy-view icon: anchored below the icon, not ANCHOR_RIGHT.
 local old=GameTooltip;local anchor,point
 GameTooltip={SetOwner=function(_,_,a) anchor=a end,ClearAllPoints=function() end,SetPoint=function(_,p) point=p end,
  SetHyperlink=function() end,SetItemKey=function() end,SetItemByID=function() end,SetText=function() end,Show=function() end,Hide=function() end}
 local ok,err=pcall(function()
  M:SetView('browse');M:RenderUI()
  M.shopBuy={key=M:Key(70,-5),name='Sandals of Healing',market={itemID=70,marketKey=M:Key(70,-5)},rows={{itemLink='|Hitem:70:x|h'}}}
  local v=M.shopScreen.buyView;v.iconButton.scripts.OnEnter(v.iconButton)
  assert(anchor=='ANCHOR_NONE' and point=='TOPLEFT','anchored below the icon')
 end)
 GameTooltip=old;M.shopBuy=nil;assert(ok,err)
end)

check('1.14.6 Auction-won chat settles a purchase whose result never came; buy view can settle it too',function()
 local function order(id,name) local e=M:AddLedger('purchase',{marketKey=id,itemID=id,name=name,quantity=1,cost=698,status='unknown',commodity=false})
  M.db.pending[e.id]=e;return e end
 for k in pairs(M.db.pending) do M.db.pending[k]=nil end
 local a=order(980,'Greenweave Sandals of Healing')
 assert(M:HasUnresolvedPurchase())
 assert(M:AuctionWonName('You won an auction for Greenweave Sandals of Healing')=='Greenweave Sandals of Healing')
 assert(not M:ResolveWonAuction('You won an auction for Something Else'),'other items do not match')
 emit('CHAT_MSG_SYSTEM','You won an auction for Greenweave Sandals of Healing')
 assert(a.status=='confirmed' and not M:HasUnresolvedPurchase(),'chat confirmed it')
 -- Buy view buttons.
 local b=order(981,'Lupine Vest of Agility')
 M:SetView('browse');M.ahOpen=true;M:RenderUI()
 M.shopBuy={key=981,name='Lupine Vest of Agility',market={itemID=981,marketKey=981,name='Lupine Vest of Agility'},rows={}}
 M.execution={state='unknown',order=b,shop=M.shopBuy,message='x'}
 local ok,lines=M:ShopBuyCheck(M.shopBuy);assert(not ok and lines[#lines]:find('Lupine Vest',1,true))
 M:RenderShopBuy();local v=M.shopScreen.buyView
 assert(v.gotIt:IsShown() and v.didnt:IsShown(),'settle buttons shown')
 local oldRefresh=M.ShopBuyRefresh;M.ShopBuyRefresh=function() end
 v.didnt.scripts.OnClick(v.didnt);M.ShopBuyRefresh=oldRefresh
 assert(b.status=='failed' and not M:HasUnresolvedPurchase(),'marked not bought')
 M:RenderShopBuy();assert(not v.gotIt:IsShown(),'buttons hide once settled')
 M.shopBuy=nil;M.execution={state='idle'};M.ahOpen=false
end)

check('1.15 Flip Ledger: confirmed buys record what you paid; mailbox sale invoices fill in what it sold for',function()
 M.db.flips={};for k in pairs(M.db.pending) do M.db.pending[k]=nil end
 local function buy(name,cost,qty)
  local e=M:AddLedger('purchase',{marketKey=990,itemID=990,name=name,quantity=qty or 1,cost=cost,status='pending',commodity=false,
   itemLink='|cff1eff00|Hitem:990::::::-10|h['..name..']|h|r'})
  M.db.pending[e.id]=e;M:ResolvePurchase(e,'confirmed','test');return e
 end
 buy('Buccaneer\'s Gloves of Healing',800);buy('Buccaneer\'s Gloves of Healing',900)
 local fails=M:AddLedger('purchase',{marketKey=991,itemID=991,name='Failed Thing',quantity=1,cost=500,status='pending'})
 M.db.pending[fails.id]=fails;M:ResolvePurchase(fails,'failed','test')
 assert(#M:FlipBook()==2,'only confirmed buys are recorded')
 -- A sale invoice from the mailbox matches the oldest unsold one.
 local oG,oH,oN=GetInboxInvoiceInfo,GetInboxHeaderInfo,GetInboxNumItems
 function GetInboxNumItems() return 1 end
 function GetInboxHeaderInfo() return nil,nil,'Auction House','Auction successful: Buccaneer\'s Gloves of Healing',3500 end
 function GetInboxInvoiceInfo() return 'seller','Buccaneer\'s Gloves of Healing','FlipBuyer',0,3500,100,175,0,0,0,1 end
 local ok,err=pcall(function()
  M.mailOpen=true;M:ObserveMail();jobs()
  local first,second=M:FlipBook()[1],M:FlipBook()[2]
  local n=M:FlipNumbers(first)
  assert(first.sold==1 and n.net==3325 and n.profit==2525 and n.status=='Sold','first sale: '..tostring(n.profit))
  assert(M:FlipNumbers(second).status=='Holding')
  M:ObserveMail();jobs();assert(M:FlipBook()[2].sold==0,'same invoice not counted twice')
  local t=M:FlipTotals();assert(t.spent==1700 and t.profit==2525 and t.holding==1 and t.holdingCost==900)
 end)
 GetInboxInvoiceInfo,GetInboxHeaderInfo,GetInboxNumItems=oG,oH,oN;M.mailOpen=false;assert(ok,err)
 -- A sale with no purchase record is still listed, cost unknown.
 M:RecordFlipSale('Mystery Cloak',1,5000,250)
 local last=M:FlipBook()[#M:FlipBook()];assert(last.cost==nil and M:FlipNumbers(last).status=='Sold (no buy record)' and M:FlipNumbers(last).profit==nil)
 -- Window renders, filters, and removes on right-click confirm.
 M:ShowFlipLedger();local f=M.flipLedger
 assert(f.rows[1]:IsShown() and f.totals:GetText():find('Holding 1',1,true),'window')
 f.filters[2].scripts.OnClick(f.filters[2]);assert(M.flipFilter=='holding' and #M:FlipRows('holding')==1)
 local oldAsk=M.AskShopConfirm;M.AskShopConfirm=function(_,_,fn) fn() end
 local r=f.rows[1];r.scripts.OnClick(r,'RightButton');M.AskShopConfirm=oldAsk
 assert(#M:FlipRows('holding')==0,'removed')
 assert(M.shopScreen.flipLedger,'Shopping has a Flip Ledger button')
 f:Hide();M.flipFilter=nil;M.db.flips={}
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
