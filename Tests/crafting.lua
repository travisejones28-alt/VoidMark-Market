return function(M,check,jobs,emit)
local bags={}
local function market(id,price,lots)
  local m={itemID=id,marketKey=id,name='Item '..id,lastSeen=time(),observations=5,confidenceScore=80,
    confidence='Established',activityScore=80,activity='High',volatility=0.05,fairValue=price,historicalFair=price,
    latest={floor=price,meaningfulFloor=price,median=price,quantity=1000,listings=100},history={}}
  m.depth={at=time(),lots=lots or {{quantity=1,cost=price,count=1000}}};M.db.market[id]=m;return m
end
local function recipe(id,item,reagents,output,learned)
  assert(M:RegisterRecipe({id=id,itemID=item,name='Recipe '..id,profession='Alchemy',reagents=reagents,
    output=output or 1,learned=learned~=false}))
  return M.db.recipes[id]
end
local function reset()
  VoidMarkMarketDB={};M.jobs={};M:InitializeDatabase();jobs();bags={}
  C_Item=C_Item or {};C_Item.GetItemCount=nil
  GetItemCount=function(id) return bags[id] or 0 end
  M.disenchantModels={};M.db.lastDepthSnapshotAt=nil
  market(101,100);market(201,1000);market(202,2000);market(203,1000)
end
check('Depth quotes exhaust cheap stock and charge complete stacks',function()
  reset();market(101,100,{{quantity=1,cost=10,count=1},{quantity=5,cost=500,count=2}})
  local q=M:QuoteAcquisition(101,3)
  assert(q.totalCost==510 and q.purchasedQuantity==6 and q.surplus==3 and #q.tiers==2)
  assert(not M:QuoteAcquisition(101,12));assert(not M:QuoteAcquisition(101,0/0))
end)
check('Depth excludes extreme high outliers and incomplete generations',function()
  reset();local m=market(101,100,{{quantity=1,cost=100,count=2},{quantity=1,cost=100000,count=1000}})
  assert(not M:QuoteAcquisition(101,3));m.depth.incomplete=true;assert(not M:QuoteAcquisition(101,1))
  m.depth.incomplete=nil;M.db.lastDepthSnapshotAt=time()+1;assert(not M:QuoteAcquisition(101,1))
  assert(not M:GetPriceInfo(101).resaleReady)
end)
check('Shared price API rejects stale, cached and suffix-only prices',function()
  reset();M.db.market[101].lastSeen=time()-99999
  assert(M.PricingAPI.GetPrice(101).status=='stale' and not M:QuoteAcquisition(101,1))
  M.db.market[101]=nil;M.db.market['101:s1']=market(999,10);assert(M.PricingAPI.GetPrice(101).status=='unavailable')
  local m=market(101,100);m.cacheUntrusted=true;assert(not M:QuoteAcquisition(101,1))
end)
check('Observed vendor bundle costs never use vendor sell value',function()
  reset();M.db.vendorMaterials[101]={price=20,bundle=5,at=time(),character=M.characterID}
  assert(M:QuoteAcquisition(101,2).totalCost==100)
  assert(M:QuoteAcquisition(101,2,{auctionOnly=true}).totalCost==200)
  M.db.vendorMaterials[101].bundle=0;assert(M:QuoteAcquisition(101,2).totalCost==200)
  M.db.market[101]=nil;assert(not M:QuoteAcquisition(101,1))
end)
check('Craft net, AH fees, deposit, ROI and breakeven match arithmetic',function()
  reset();local r=recipe('a',201,{{itemID=101,quantity=2}})
  local e=M:EvaluateCraft(r,1)
  assert(e.cost==200 and e.gross==1000 and e.fee==50 and e.depositReserve==100)
  assert(e.netIfSold==650 and e.net==460 and e.roi==2.3 and e.breakeven==395 and e.pass)
  assert(e.buyFinished==1000 and e.makeSaving==800)
end)
check('Owned reagents reduce cash without manufacturing profit',function()
  reset();bags[101]=3;local r=recipe('a',201,{{itemID=101,quantity=2}})
  local e=M:EvaluateCraft(r,1);assert(e.cost==200 and e.cashCost==0 and e.net==460)
  GetItemCount=nil;assert(not M:EvaluateCraft(r,1).pass)
end)
check('Multi-stage crafting chooses cheaper known intermediate',function()
  reset();recipe('a',201,{{itemID=101,quantity=2}})
  local r=recipe('b',202,{{itemID=201,quantity=1},{itemID=101,quantity=1}})
  local e=M:EvaluateCraft(r,1);assert(e.cost==300 and #e.steps==1 and e.materials[101].quantity==3)
  bags[201]=1;e=M:EvaluateCraft(r,1);assert(e.cashCost==100 and e.cost==300)
end)
check('Repeated chain ingredients share depth instead of reusing cheap stock',function()
  reset();market(101,100,{{quantity=1,cost=10,count=1},{quantity=1,cost=100,count=99}})
  recipe('a',201,{{itemID=101,quantity=2}})
  local r=recipe('b',202,{{itemID=201,quantity=1},{itemID=101,quantity=1}})
  assert(M:EvaluateCraft(r,1).cost==210)
end)
check('Chain surplus output is reused and recursive cycles terminate',function()
  reset();recipe('a',201,{{itemID=101,quantity=2}},2)
  local r=recipe('b',202,{{itemID=201,quantity=3}});assert(M:EvaluateCraft(r,1).cost==400)
  recipe('cycle',101,{{itemID=202,quantity=1}})
  M.db.market[101]=nil;M.db.market[201]=nil;M.db.market[202]=nil
  local e=M:EvaluateCraft(r,1);assert(e.status=='UNPRICED')
end)
check('Unlearned recipes are visible but cannot become crafting candidates',function()
  reset();local r=recipe('a',201,{{itemID=101,quantity=2}},1,false)
  assert(not M:EvaluateCraft(r,1).pass);assert(#M:RecipeCandidates(201)==0)
end)
check('Missing prices and unreliable output history never invent profits',function()
  reset();local r=recipe('a',201,{{itemID=101,quantity=2}})
  M.db.market[101]=nil;assert(M:EvaluateCraft(r,1).net==nil)
  market(101,100);M.db.market[201].observations=1;assert(M:EvaluateCraft(r,1).net==nil)
end)
check('Investment caps and conservative output limits block crafting',function()
  reset();local r=recipe('a',201,{{itemID=101,quantity=2}})
  M.db.settings.maxTransaction=100;assert(not M:EvaluateCraft(r,1).pass)
  M.db.settings.maxTransaction=100000;M.db.market[201].latest.quantity=1;assert(not M:EvaluateCraft(r,2).pass)
end)
check('Two projects consume shared bags once and combine reagent depth',function()
  reset();bags[101]=3;recipe('a',201,{{itemID=101,quantity=2}});recipe('b',203,{{itemID=101,quantity=2}})
  assert(M:SetCraftPlan('a',1));assert(M:SetCraftPlan('b',1))
  local p=M:BuildCraftShopping();assert(#p.rows==1 and p.rows[1].owned==3 and p.rows[1].missing==1 and p.cost==100)
  assert(p.complete and p.rows[1].maxUnit and p.rows[1].maxUnit>0)
  assert(M:SetCraftPlan('a',0));assert(M:BuildCraftShopping().cost==0)
end)
check('Combined plans respect portfolio limits and withhold unsafe caps',function()
  reset();recipe('a',201,{{itemID=101,quantity=2}});recipe('b',203,{{itemID=101,quantity=2}})
  M.db.settings.maxTransaction=300;M:SetCraftPlan('a',1);M:SetCraftPlan('b',1)
  local p=M:BuildCraftShopping();assert(not p.complete and p.rows[1].maxUnit==nil)
end)
check('Projects and learned recipes survive reload without changing safety or ledger',function()
  reset();recipe('a',201,{{itemID=101,quantity=2}});M:SetCraftPlan('a',2)
  local old=M.db;M.db.settings.safeMode=false;M:InitializeDatabase();jobs()
  assert(M.db==old and #M:BuildCraftShopping().projects==1 and M:KnownRecipe(M.db.recipes.a))
  assert(M.db.settings.safeMode and #M.db.ledger==0)
  M.characterID='Other';assert(#M:BuildCraftShopping().projects==0 and not M:KnownRecipe(M.db.recipes.a))
end)
check('Legacy profession reader handles output yields and uncached links',function()
  reset();GetNumTradeSkills=function() return 2 end;GetTradeSkillLine=function() return 'Alchemy' end
  GetTradeSkillInfo=function(i) return 'Potion '..i,'optimal' end
  GetTradeSkillItemLink=function(i) return '|Hitem:'..(200+i)..'|h' end
  GetTradeSkillNumMade=function() return 2,2 end
  GetTradeSkillNumReagents=function() return 1 end
  GetTradeSkillReagentInfo=function() return 'Herb',1,3 end
  GetTradeSkillReagentItemLink=function(i) if i==1 then return '|Hitem:101|h' end end
  M:CaptureProfession();jobs();local n=0;for _,r in pairs(M.db.recipes) do n=n+1;assert(r.output==2 and r.reagents[1].quantity==3) end
  assert(n==1 and M.recipeDiagnostic:find('1 recipes captured'))
  GetNumTradeSkills=nil
end)
check('Modern reader records learnable recipes and rejects optional-choice slots',function()
  reset();C_TradeSkillUI={GetAllRecipeIDs=function() return {1,2} end,
    GetRecipeInfo=function() return {name='Potion',learned=false} end,
    GetRecipeItemLink=function() return '|Hitem:201|h' end,
    GetRecipeSchematic=function(id) return {quantityMin=1,quantityMax=1,reagentSlotSchematics={
      {quantityRequired=id==1 and 2 or 0,reagents={{itemID=101}}}}} end}
  M:CaptureProfession();jobs();assert(M.db.recipes['spell:1'] and not M:KnownRecipe(M.db.recipes['spell:1']))
  assert(not M.db.recipes['spell:2']);C_TradeSkillUI=nil
end)
check('Merchant capture rejects limited stock and extended currencies',function()
  reset();GetMerchantNumItems=function() return 3 end
  GetMerchantItemLink=function(i) return '|Hitem:'..(100+i)..'|h' end
  GetMerchantItemInfo=function(i) return 'Reagent',1,100,5,i==2 and 1 or -1,true,true,i==3 end
  M:CaptureVendorMaterials();jobs();assert(M.db.vendorMaterials[101] and not M.db.vendorMaterials[102] and not M.db.vendorMaterials[103])
end)
check('Craft rankings run incrementally and stale results cannot leak to Nexus',function()
  reset();recipe('a',201,{{itemID=101,quantity=2}});M:RebuildCrafting();assert(M.craftingBusy);assert(jobs()>1)
  assert(#M.PricingAPI.GetCraftingOpportunities()==1)
  M.db.market[101].lastSeen=time()-10000;assert(#M.PricingAPI.GetCraftingOpportunities()==0)
  assert(M:GetCraftRows('','score')[1].status=='STALE')
end)
check('Farming comparisons require measured yield and established resale',function()
  reset();assert(not M.PricingAPI.GetFarmingComparison(201,0))
  local p=M.PricingAPI.GetFarmingComparison(201,10);assert(p.netPerHour==8500)
  M.db.market[201].observations=1;assert(not M.PricingAPI.GetFarmingComparison(201,10))
end)
check('Disenchant distributions validate probabilities and suppress unknown outputs',function()
  reset();assert(not M:RegisterDisenchantModel(101,{verified=true,source='test',outcomes={{probability=0.8,items={}}}}))
  assert(M:RegisterDisenchantModel(101,{verified=true,source='verified fixture',outcomes={{probability=1,items={{itemID=201,quantity=1}}}}}))
  assert(M:EvaluateDisenchant(101).economics.net==560)
  M.db.market[201]=nil;assert(not M:EvaluateDisenchant(101))
end)
check('New UI renders sorting, filters, plan editing and calculation details without transactions',function()
  reset();local r=recipe('a',201,{{itemID=101,quantity=2}});M:RebuildCrafting();jobs()
  M.db.settings.filter='';M:SetView('crafting');M:RenderUI();assert(M.rows[1].data.recipe==r)
  M.rows[1].scripts.OnClick(M.rows[1]);M.craftQuantity:SetText('2');M.planCraftButton.scripts.OnClick();M:RenderUI()
  assert(#M.craftShopping.projects==1)
  M:ShowCraftCalculations(M.selectedRow);assert(M.craftDetailText:GetText():find('AH cut'))
  M.db.settings.filter='no matches';M:RenderUI();assert(not M.rows[1]:IsShown())
  M.db.settings.filter=''
  for _,view in ipairs({'materials','goldmaking','market','crafting'}) do M:SetView(view);jobs();M:RenderUI() end
  assert(M.db.settings.safeMode and #M.db.ledger==0 and next(M.db.pending)==nil)
end)
check('Real scanner publishes whole-stack depth, excludes own asks and invalidates absent stock',function()
  reset();M.ahOpen=true
  local oldInfo,oldLink,oldCount=C_AuctionHouse.GetReplicateItemInfo,C_AuctionHouse.GetReplicateItemLink,C_AuctionHouse.GetNumReplicateItems
  C_AuctionHouse.GetNumReplicateItems=function() return 3 end
  C_AuctionHouse.GetReplicateItemInfo=function(i)
    return 'Herb',1,1,1,true,1,0,0,0,i==0 and 10 or 100,0,false,nil,i==0 and UnitName('player') or 'Seller','Seller-TestRealm',0,101,true
  end
  C_AuctionHouse.GetReplicateItemLink=function() return '|Hitem:101:0:0:0:0:0:0:0|h[Herb]|h' end
  -- Mark a previous output snapshot older so absence is visible in this generation.
  M.db.market[201].lastSeen=time()-1
  M:StartSnapshotProcessing(3,'fresh replicate request');jobs()
  local q=M:QuoteAcquisition(101,2);assert(q and q.totalCost==200 and q.availableQuantity==2)
  assert(not M:QuoteAcquisition(101,3));assert(not M:QuoteAcquisition(201,1))
  C_AuctionHouse.GetReplicateItemInfo,C_AuctionHouse.GetReplicateItemLink,C_AuctionHouse.GetNumReplicateItems=oldInfo,oldLink,oldCount
end)
check('Malformed recipe input and excessive chain depth fail safely',function()
  reset();assert(not M:RegisterRecipe({id='bad',name='Bad',profession='Test',itemID=201,output=1,
    reagents={{itemID=101,quantity=0/0}},learned=true}))
  for i=1,10 do recipe('chain'..i,300+i,{{itemID=301+i,quantity=1}}) end
  market(311,1);local e=M:EvaluateCraft(M.db.recipes.chain1,1);assert(e.status=='UNPRICED')
end)
end
