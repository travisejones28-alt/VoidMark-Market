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
 -- 1.18: quotes keep Auctionator's exact-name meaning; item-level fields (3-4) are not required level.
 assert(table.concat(M:ShopTerms('Greens Flip'),',')=='of the Monkey,"of the Tiger",of the Bear',table.concat(M:ShopTerms('Greens Flip'),','))
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
 assert(M:HasUnknownPurchase() and not M:HasUnresolvedPurchase(),'unknown item buy: reminder, not a block')
 assert(M:AuctionWonName('You won an auction for Greenweave Sandals of Healing')=='Greenweave Sandals of Healing')
 assert(not M:ResolveWonAuction('You won an auction for Something Else'),'other items do not match')
 emit('CHAT_MSG_SYSTEM','You won an auction for Greenweave Sandals of Healing')
 assert(a.status=='confirmed' and not M:HasUnknownPurchase(),'chat confirmed it')
 -- Buy view buttons.
 local b=order(981,'Lupine Vest of Agility')
 M:SetView('browse');M.ahOpen=true;M:RenderUI()
 M.shopBuy={key=981,name='Lupine Vest of Agility',market={itemID=981,marketKey=981,name='Lupine Vest of Agility'},rows={}}
 M.execution={state='unknown',order=b,shop=M.shopBuy,message='x'}
 local ok,lines=M:ShopBuyCheck(M.shopBuy);local seen=false;for _,l in ipairs(lines) do if l:find('Lupine Vest',1,true) then seen=true end end;assert(seen,'reminder shown')
 M:RenderShopBuy();local v=M.shopScreen.buyView
 assert(v.gotIt:IsShown() and v.didnt:IsShown(),'settle buttons shown')
 local oldRefresh=M.ShopBuyRefresh;M.ShopBuyRefresh=function() end
 v.didnt.scripts.OnClick(v.didnt);M.ShopBuyRefresh=oldRefresh
 assert(b.status=='failed' and not M:HasUnknownPurchase(),'marked not bought')
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
 assert(f.rows[1]:IsShown() and f.totals2:GetText():find('Holding 1',1,true),'window')
 f.filters[2].scripts.OnClick(f.filters[2]);assert(M.flipFilter=='holding' and #M:FlipRows('holding')==1)
 local oldAsk=M.AskShopConfirm;M.AskShopConfirm=function(_,_,fn) fn() end
 local r=f.rows[1];r.scripts.OnClick(r,'RightButton');M.AskShopConfirm=oldAsk
 assert(#M:FlipRows('holding')==0,'removed')
 assert(M.shopScreen.flipLedger,'Shopping has a Flip Ledger button')
 f:Hide();M.flipFilter=nil;M.db.flips={}
end)

check('1.15.1 Lvl fills in once the game loads an uncached item',function()
 fresh();M:SetView('browse');M.ahOpen=false
 local oldInfo,oldC=GetItemInfo,C_Item;local loaded,asked=false,{}
 GetItemInfo=function(id) if id==970 and loaded then return 'X','l',2,30,23 end end
 C_Item=setmetatable({RequestLoadItemDataByID=function(id) asked[#asked+1]=id end},{__index=oldC})
 local ok,err=pcall(function()
  M.browseRows={{marketKey=970,itemID=970,name='Watcher\'s Cinch of Intellect',floor=1000,quantity=1,status='LIVE BROWSE'}}
  M:RenderUI();local s=M.shopScreen
  assert(s.rows[1].c[5]:GetText():find('--',1,true) and asked[1]==970,'asked the game to load it')
  M:RenderUI();assert(#asked==1,'asked only once')
  loaded=true;M.uiDirty=false;emit('GET_ITEM_INFO_RECEIVED',970,true)
  assert(M.uiDirty,'arrival redraws');M:RenderUI()
  assert(s.rows[1].c[5]:GetText()=='23','level shown: '..s.rows[1].c[5]:GetText())
 end)
 GetItemInfo,C_Item=oldInfo,oldC;assert(ok,err)
end)

check('1.15.2 Listings: the selected auction verdict sits in the header, not on the gold totals line',function()
 M:SetView('my auctions');M:RenderUI();local s=M.cancelScreen
 if not s then return end
 M.selectedRow={name="Buccaneer's Gloves",reason='Nobody else is selling this. Keep it.'}
 M:RenderUI()
 assert(s.reason:GetText():find('Nobody else is selling',1,true),'verdict in header')
 assert(not tostring(s.summary:GetText()):find('Nobody else',1,true),'not on the summary line')
 M.selectedRow=nil;M:SetView('browse')
end)

check('1.15.3 Live results find scan data saved under another item-level label (Vs Avg and tooltip link)',function()
 local scanKey=M:Key(1010,-10,24)            -- full scan: gear labeled with its item level
 local liveKey=M:Key(1010,-10)               -- live search: no level
 local h={};for i=1,3 do h[i]={at=time()-i*3600,median=2000} end
 M.db.market[scanKey]={itemID=1010,itemSuffix=-10,itemLevel=24,marketKey=scanKey,name="Sage's Sash of Intellect",latest={},history=h,
  itemLink='|cff1eff00|Hitem:1010:0:0:0:0:0:-10:123|h[Sage\'s Sash of Intellect]|h|r',lastSeen=time()}
 M:RebuildIndexes();jobs()
 assert(M:MarketForKey(liveKey)==M.db.market[scanKey],'found by item + suffix')
 assert(M:MarketForKey(M:Key(1010,-11))==nil,'other suffixes never match')
 assert(M:DealRatio({marketKey=liveKey,floor=1000})==50,'Vs Avg uses the scan history')
 local shown;local tip={SetHyperlink=function(_,l) shown=l end,SetItemKey=function() shown='key' end,SetItemByID=function() end}
 assert(M:SetVariantTooltip(tip,liveKey,1010)=='link' and shown:find('1010:0:0:0:0:0:-10',1,true),'scan link used for the tooltip')
 assert(M:SetVariantTooltip(tip,M:Key(1011,15),1011)=='built' and shown=='item:1011:0:0:0:0:0:15','fixed suffix builds a link')
 M.db.market[scanKey]=nil;M:RebuildIndexes();jobs()
end)

check('1.15.4 Item tooltips show Last Bought / Last Sold; Ctrl adds when, who and averages',function()
 M.db.flips={}
 local link='|cff1eff00|Hitem:1020:0:0:0:0:0:-10|h[Sage\'s Sash of Intellect]|h|r'
 M:RecordFlipBuy({name="Sage's Sash of Intellect",itemID=1020,marketKey=M:Key(1020,-10),quantity=1,cost=950})
 M:RecordFlipBuy({name="Sage's Sash of Intellect",itemID=1020,marketKey=M:Key(1020,-10),quantity=1,cost=1150})
 M:FlipBook()[2].at=M:FlipBook()[1].at+60
 M:RecordFlipSale("Sage's Sash of Intellect",1,4900,245)
 local lines={};local tip={AddLine=function(_,t) lines[#lines+1]=t end,AddDoubleLine=function(_,l,r) lines[#lines+1]=l..'='..r end}
 local oldCtrl=IsControlKeyDown
 IsControlKeyDown=function() return false end
 M:AppendBoughtTooltip(tip,link)
 assert(lines[1]=='Last Bought='..M:Coins(1150) and lines[2]=='Last Sold='..M:Coins(4900) and lines[3]:find('Hold Ctrl',1,true),table.concat(lines,' / '))
 lines={};IsControlKeyDown=function() return true end
 M:AppendBoughtTooltip(tip,link)
 local all=table.concat(lines,' / ')
 assert(all:find('  bought=',1,true) and all:find('after cut',1,true) and all:find('Bought 2 times=avg '..M:Coins(1050),1,true),all)
 lines={};M:AppendBoughtTooltip(tip,'|cff1eff00|Hitem:1021|h[Other Item]|h|r');assert(#lines==0,'nothing for items never traded')
 IsControlKeyDown=oldCtrl;M.db.flips={}
end)

check('1.16 Flip Ledger: outside buys, listing price, expired deposits, days to sell and profit',function()
 M.db.flips={};for k in pairs(M.db.pending) do M.db.pending[k]=nil end
 M.execution={state='idle'}
 -- Bought on the normal AH: the bid sent + the "won" message.
 M:NoteOutsideBid(501,1200)
 emit('CHAT_MSG_SYSTEM','You won an auction for Lupine Vest of Agility')
 local f=M:FlipBook()[1]
 assert(f and f.cost==1200 and f.name=='Lupine Vest of Agility' and f.source=='AH','outside buy recorded')
 -- Market's own bid is never double counted.
 M.execution={state='pending',live={auctionID=777}};M:NoteOutsideBid(777,999);M.execution={state='idle'}
 assert(#(M.outsideBids or {})==0,'own purchase bid ignored')
 emit('CHAT_MSG_SYSTEM','You won an auction for Unrelated Thing');assert(#M:FlipBook()==1,'no bid, nothing recorded')
 -- Listed (from your auctions).
 f.at=time()-2*86400
 M:UpdateFlipListings({{name='Lupine Vest of Agility',unit=4500,quantity=1,deposit=60}})
 assert(f.listPrice==4500 and f.deposit==60 and M:FlipNumbers(f).status=='Listed')
 -- Expired once: deposit lost, back to holding.
 M:RecordFlipExpired('Lupine Vest of Agility')
 assert(f.expired==1 and f.depositsLost==60 and M:FlipNumbers(f).status=='Holding (expired x1)')
 -- Relisted and sold: profit = after cut - paid - lost deposit; days to sell.
 M:UpdateFlipListings({{name='Lupine Vest of Agility',unit=4000,quantity=1,deposit=60}})
 M:RecordFlipSale('Lupine Vest of Agility',1,4000,200)
 local n=M:FlipNumbers(f)
 assert(n.status=='Sold' and n.net==3800 and n.profit==3800-1200-60 and n.days>=1.9 and n.days<=2.1,'sold numbers '..tostring(n.profit))
 assert(math.abs(n.roi-(2540/1200))<0.001,'roi')
end)

check('1.16 Flip Ledger summaries by item and by suffix, time periods, sorting and CSV',function()
 M.db.flips={}
 local function flip(name,cost,sold,ageDays)
  local f=M:RecordFlipBuy({name=name,quantity=1,cost=cost});f.at=time()-ageDays*86400
  if sold then M:RecordFlipSale(name,1,sold,math.floor(sold*0.05)) end
  return f
 end
 flip('Bandit Boots of the Monkey',500,3000,1);flip('Bandit Boots of the Monkey',700,nil,1)
 flip('Scouting Tunic of the Monkey',900,2000,1);local old=flip('Sage\'s Sash of Intellect',800,600,10);old.soldAt=time()-9*86400
 assert(M:FlipSuffix('Bandit Boots of the Monkey')=='of the Monkey' and M:FlipSuffix("Sage's Sash of Intellect")=='of Intellect' and M:FlipSuffix('Linen Cloth')=='No suffix')
 local by={};for _,g in ipairs(M:FlipGroups('item')) do by[g.name]=g end
 local boots=by['Bandit Boots of the Monkey']
 assert(boots.bought==2 and boots.sold==1 and boots.holding==1 and boots.avgPaid==600 and boots.avgSold==2850 and boots.profit==2350,'by item')
 local suf={};for _,g in ipairs(M:FlipGroups('suffix')) do suf[g.name]=g end
 assert(suf['of the Monkey'].sold==2 and suf['of the Monkey'].profit==2350+1000 and suf['of Intellect'].profit==570-800,'by suffix')
 -- 7-day period drops the buy from 10 days ago (sold 9 days ago); bought OR sold in the period counts.
 assert(#M:FlipRows('all','week')==3 and #M:FlipRows('all','all')==4,'period')
 assert(M:FlipTotals('week').spent==2100,'week totals')
 -- Window: views, sort by header, CSV.
 M.flipView=nil;M.flipSort=nil;M:ShowFlipLedger();local f=M.flipLedger
 f.views[3].scripts.OnClick(f.views[3]);assert(M.flipView=='bysuffix' and f.rows[1].c[1]:GetText()=='of the Monkey','suffix view, best profit first')
 f.views[2].scripts.OnClick(f.views[2]);assert(f.headers[7].text:GetText()=='ROI')
 f.headers[2].scripts.OnClick(f.headers[2]);assert(f.rows[1].c[1]:GetText()=='Bandit Boots of the Monkey','sorted by bought')
 f.views[1].scripts.OnClick(f.views[1]);assert(f.headers[4].text:GetText()=='Listed at')
 local csv=M:FlipLedgerCSV();assert(csv:find('^Item,Quantity,Paid') and select(2,csv:gsub('\n',''))==4,'csv rows')
 f:Hide();M.flipView=nil;M.flipSort=nil;M.db.flips={}
end)

check('1.16 Selling shows what you paid for the selected item',function()
 M.db.flips={};M:RecordFlipBuy({name='Lupine Vest of Agility',quantity=1,cost=1450})
 assert(M:SellPaidText({name='Lupine Vest of Agility',itemLink='|cff1eff00|Hitem:5|h[Lupine Vest of Agility]|h|r'}):find(M:Coins(1450),1,true))
 assert(M:SellPaidText({name='Never Bought'})=='')
 M:SetView('selling');M.selectedRow={name='Lupine Vest of Agility',itemID=5,itemLink='|cff1eff00|Hitem:5|h[Lupine Vest of Agility]|h|r'}
 local ok,err=pcall(function() M:RenderUI() end)
 if ok and M.sellScreen and M.sellScreen.info then assert(M.sellScreen.info:GetText():find('You paid',1,true),'paid shown in the info line') end
 M.selectedRow=nil;M:SetView('browse');M.db.flips={};assert(ok,err)
end)

check('1.17 Vs Avg uses daily lows from live searches, then the item across all suffixes (marked ~)',function()
 M.db.dailyLows={};M.db.dailyLowsBase={}
 local key=M:Key(1030,-10);local other=M:Key(1030,-12)
 local today=math.floor(time()/86400)
 -- Two days of live-search lows for this exact variant.
 M.db.dailyLows[tostring(key)]={[today-2]=3000,[today-1]=5000}
 local pct,ref,approx=M:DealRatio({marketKey=key,floor=2000})
 assert(pct==50 and ref==4000 and not approx,'exact variant from daily lows: '..tostring(pct))
 -- A suffix with no history of its own falls back to the base item, marked ~.
 M.db.dailyLowsBase[1030]={[today-3]=2000,[today-1]=2400}
 pct,ref,approx=M:DealRatio({marketKey=other,floor=1100})
 assert(pct==50 and approx,'base fallback')
 assert(M:DealText({marketKey=other,floor=1100}):find('~50%',1,true),'shown with ~')
 -- Recording: the lowest per day wins and old days drop off.
 M.db.dailyLows={};M.db.dailyLowsBase={}
 M:RecordDailyLow(key,900);M:RecordDailyLow(key,700);M:RecordDailyLow(key,800)
 assert(M.db.dailyLows[tostring(key)][today]==700 and M.db.dailyLowsBase[1030][today]==700)
 M.db.dailyLows[tostring(key)][today-40]=1;M:RecordDailyLow(key,750);assert(M.db.dailyLows[tostring(key)][today-40]==nil,'30-day window')
 -- Live searches feed it.
 M:RecordLiveFloor(M:Key(1031,-10),555,1);assert(M.db.dailyLows[tostring(M:Key(1031,-10))][today]==555)
 M.db.dailyLows={};M.db.dailyLowsBase={}
end)

check('1.17 A failed AH search ends that request instead of waiting for a timeout',function()
 local q=M.queue;local failed
 q.active={id='x',kind='browse',sent=0};q.dedupe.x=q.active;q.active.fail=function(e) failed=e end
 emit('AUCTION_HOUSE_BROWSE_FAILURE')
 assert(failed=='Auction House search failed' and q.active==nil)
 q.dedupe={}
end)

check('1.18 Auctionator extended terms import with their category, level, price and quality',function()
 fresh();M.db.shopTerms=nil
 local c=function(t) return M:AuctionatorTermToMarket(t) end
 assert(c('agility;Armor/Leather;0;0;0;0;0;0;0;0.5;0;0;0;0')=='leather: agility max 50s',c('agility;Armor/Leather;0;0;0;0;0;0;0;0.5;0;0;0;0'))
 assert(c('intellect;Armor/Cloth;0;0;15;0;0;0;0;0;0;0;0;0')=='cloth: intellect lvl 15+')
 assert(c(';Armor/Leather/Head;0;0;0;0;0;0;0;0.75;0;0;0;0')=='leather head: max 75s')
 assert(c('healing;Armor/Cloth;0;0;20;40;0;0;0;1.25;2;0;0;0')=='green cloth: healing lvl 20-40 max 1g25s')
 assert(c('"Lupine Vest";;0;0;0;0')=='"Lupine Vest"')
 -- A list called "shopping" goes into your main Shopping list (one list for everything).
 local ok,msg=M:ImportShoppingTransfer('shopping^magic;Armor/Cloth;0;0;0;0;0;0;0;0;0;0;0;0^agility;Armor/Leather;0;0;0;0;0;0;0;0.5;0;0;0;0')
 assert(ok,msg);local t=M:ShopTerms('Shopping')
 assert(t[1]=='cloth: magic' and t[2]=='leather: agility max 50s' and not M.db.shoppingLists['shopping'],'merged into Shopping')
 -- The converted terms parse back with the right filters.
 local text,armor,spec=M:ParseShopTerm('green cloth: healing lvl 20-40 max 1g25s')
 assert(text=='healing' and armor==1 and spec.quality==2 and spec.minLevel==20 and spec.maxLevel==40 and spec.max==12500)
 text,armor,spec=M:ParseShopTerm('"Lupine Vest of Agility"');assert(text=='Lupine Vest of Agility' and spec.exact)
 M.db.shopTerms=nil
end)

check('1.18 Quality and exact-name terms: greens-only query to the server, other qualities and names dropped',function()
 fresh();M:SetView('browse');M.ahOpen=true;M.queue.nextSend=0
 local A=C_AuctionHouse;local o={A.GetBrowseResults,A.SendBrowseQuery,A.GetItemKeyInfo,Enum.AuctionHouseFilter}
 local sent
 Enum.AuctionHouseFilter=Enum.AuctionHouseFilter or {PoorQuality=1,CommonQuality=2,UncommonQuality=3,RareQuality=4,EpicQuality=5}
 A.SendBrowseQuery=function(q) sent=q end
 A.GetItemKeyInfo=function(k) return ({[1040]={itemName='Lupine Vest of Agility',quality=2},[1041]={itemName='Lupine Vest of Agility',quality=3},
  [1042]={itemName='Lupine Vest of the Monkey',quality=2}})[k.itemID] end
 A.GetBrowseResults=function() return {
  {itemKey={itemID=1040,itemSuffix=0,itemLevel=0},minPrice=900,totalQuantity=1},
  {itemKey={itemID=1041,itemSuffix=0,itemLevel=0},minPrice=900,totalQuantity=1},
  {itemKey={itemID=1042,itemSuffix=0,itemLevel=0},minPrice=900,totalQuantity=1}} end
 local ok,err=pcall(function()
  M:SetList('Flips');M:AddShopTerm('Flips','green: "Lupine Vest of Agility"')
  M:OpenShoppingList('Flips');M.queue.nextSend=0;M:PumpQueue();emit('AUCTION_HOUSE_BROWSE_RESULTS_UPDATED')
  assert(sent.searchString=='Lupine Vest of Agility' and sent.filters[1]==Enum.AuctionHouseFilter.UncommonQuality,'greens-only query')
  local rows=M:ShoppingResultRows();assert(#rows==1 and rows[1].itemID==1040,'only the green exact match: '..#rows)
 end)
 A.GetBrowseResults,A.SendBrowseQuery,A.GetItemKeyInfo,Enum.AuctionHouseFilter=o[1],o[2],o[3],o[4]
 M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
 M:DeleteShoppingList('Flips');assert(ok,err)
end)

check('1.18 An unconfirmed item buy no longer blocks buying; in-flight buys and commodity buys still do',function()
 for k in pairs(M.db.pending) do M.db.pending[k]=nil end
 local function add(status,commodity) local e=M:AddLedger('purchase',{name='X',quantity=1,cost=1,status=status,commodity=commodity});M.db.pending[e.id]=e;return e end
 local u=add('unknown',false);assert(M:HasUnknownPurchase() and not M:HasUnresolvedPurchase(),'item unknown: reminder only')
 local c=add('unknown',true);assert(M:HasUnresolvedPurchase(),'commodity unknown still blocks')
 M.db.pending[c.id]=nil
 local f=add('pending',false);assert(M:HasUnresolvedPurchase(),'in flight blocks')
 for k in pairs(M.db.pending) do M.db.pending[k]=nil end
 assert(M:LedgerTotals().reserved==0)
end)

check('1.19 Never sell below what you paid: post price is held at paid + AH cut; held flips listed first',function()
 M.db.flips={};M.db.sellFloors={}
 M:RecordFlipBuy({name='Lupine Vest of Agility',itemID=1050,marketKey=1050,quantity=1,cost=1900})
 local row={name='Lupine Vest of Agility',itemID=1050,marketKey=1050,itemLink='|cff1eff00|Hitem:1050|h[Lupine Vest of Agility]|h|r'}
 assert(M:PaidFloor(row)==2000,'1900 / 0.95')
 local unit,held,why=M:SuggestPostUnit(row,1500,false)
 assert(unit==2000 and held and why=='paid','held at paid: '..tostring(unit))
 assert(M:SuggestPostUnit(row,5000,false)==4900,'above the floor: normal undercut')
 -- A higher custom minimum still wins.
 M.db.sellFloors[1050]=3000;unit,held,why=M:SuggestPostUnit(row,1500,false);assert(unit==3000 and why=='minimum')
 M.db.sellFloors={}
 SlashCmdList.VOIDMARKMARKET('paidfloor off');assert(M:PaidFloor(row)==nil and M:SuggestPostUnit(row,1500,false)==1400)
 SlashCmdList.VOIDMARKMARKET('paidfloor on');assert(M:PaidFloor(row)==2000)
 -- Sold: no floor any more.
 M:RecordFlipSale('Lupine Vest of Agility',1,4000,200);assert(M:PaidFloor(row)==nil)
 -- Held flips first in the Selling bag list.
 M:RecordFlipBuy({name='Zebra Flip of the Bear',itemID=1051,marketKey=1051,quantity=1,cost=100})
 local tiles=M:SellTiles({{name='Apple',itemID=1,marketKey=1,quantity=1},{name='Zebra Flip of the Bear',itemID=1051,marketKey=1051,quantity=1}})
 assert(tiles[1].row.name=='Zebra Flip of the Bear' and tiles[1].held,'held flip first')
 M.db.flips={}
end)

check('1.19 Daily lows are capped; /vmm check reports how an item is labeled and what is saved',function()
 M.db.dailyLows={};local today=math.floor(time()/86400)
 for i=1,120 do M.db.dailyLows['k'..i]={[today-(i%25)]=100} end
 local dropped=M:PruneDailyLows('dailyLows',100);local n=0;for _ in pairs(M.db.dailyLows) do n=n+1 end
 assert(dropped==35 and n==85,'pruned to 85% of the cap: '..n)
 for _,t in pairs(M.db.dailyLows) do for d in pairs(t) do assert(d>=today-24) end end
 M.db.dailyLows={};M.db.dailyLowsBase={}
 local printed={};local oldPrint=M.Print;M.Print=function(_,t) printed[#printed+1]=t end
 local ok,err=pcall(function()
  assert(M:CheckItem('|cff1eff00|Hitem:1060:0:0:0:0:0:-10|h[Test Item of the Bear]|h|r'))
  local all=table.concat(printed,'\n')
  assert(all:find('link key',1,true) and all:find('saved prices: none',1,true) and all:find('Vs Avg reference: none yet',1,true),all)
  printed={};assert(not M:CheckItem(nil) and printed[1]:find('Hover an item',1,true))
 end)
 M.Print=oldPrint;assert(ok,err)
end)

check('1.20 Flip Ledger is its own AH tab; the Shopping button opens that tab',function()
 M.db.flips={};M:RecordFlipBuy({name='Tab Test Vest',quantity=1,cost=500})
 M:SetView('flip ledger');M:RenderUI()
 assert(M.flipScreen and M.flipScreen:IsShown() and not M.shopScreen:IsShown(),'tab screen shown')
 assert(M.flipScreen.rows[1]:IsShown() and M.flipScreen.rows[1].c[1]:GetText()=='Tab Test Vest','renders rows')
 M:SetView('browse');M:RenderUI();assert(not M.flipScreen:IsShown(),'hidden on other tabs')
 local clicked;local oldTabs,oldOpen=M.auctionTabs,M.ahOpen
 M.auctionTabs={{key='flipledger',button={GetScript=function() return function() clicked=true end end}}};M.ahOpen=true
 M:ShowFlipLedger();assert(clicked,'switches to the tab while the AH is open')
 M.auctionTabs,M.ahOpen=oldTabs,oldOpen;M.db.flips={}
 local found;for _,sec in ipairs(M.auctionSections) do if sec.key=='flipledger' then found=sec end end
 assert(found and found.root=='flip ledger' and found.label=='Flip Ledger')
end)

check('1.20.1 History is never dropped: old sold rows fold into per-item totals; held items always kept',function()
 M.db.flips={};M.db.flipArchive={}
 local book=M:FlipBook()
 for i=1,5003 do book[i]={id=i,name=i<=3 and 'Old Sold Thing' or 'Bulk',qty=1,cost=100,at=time(),sold=1,gross=300,fee=15,soldAt=time()} end
 book[1].name='Old Sold Thing';book[5003].sold=0;book[5003].gross=0;book[5003].fee=0 -- one still held
 M:RecordFlipBuy({name='New Buy',quantity=1,cost=50}) -- triggers the trim
 assert(#M:FlipBook()==5000,'trimmed to 5000: '..#M:FlipBook())
 local a=M.db.flipArchive['Old Sold Thing'];assert(a and a.bought==3 and a.sold==3 and a.profit==3*185,'folded into totals')
 local g;for _,x in ipairs(M:FlipGroups('item')) do if x.name=='Old Sold Thing' then g=x end end
 assert(g and g.sold==3 and g.profit==555,'still in By item')
 local t=M:FlipTotals('all');assert(t.profit>=555*1,'all-time totals include it')
 -- Every row held: nothing is dropped.
 M.db.flips={};book=M:FlipBook();for i=1,5001 do book[i]={id=i,name='Held',qty=1,cost=1,at=time(),sold=0} end
 M:RecordFlipBuy({name='Held',quantity=1,cost=1});assert(#M:FlipBook()==5002,'held rows never dropped')
 M.db.flips={};M.db.flipArchive={}
end)

check('1.20.1 A failed scan says why, and that older prices are still used',function()
 local old=M.scanState.phase;local oldD=M.scanState.fullScanDiagnostic
 M.scanState.phase='error';M.scanState.fullScanDiagnostic={error='Full scan: no replicate response after 180s; listening for late response'}
 local t=M:SimpleScanStatus()
 assert(t:find('no replicate response after 180s',1,true) and not t:find('Full scan:',1,true),t)
 M.scanState.phase=old;M.scanState.fullScanDiagnostic=oldD
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
