return function(M,check,jobs,advance,emit)
-- 1.11.0 Disenchant advisor (CraftShuffle yield tables) in tooltips and a bag check window.
local items={
 -- id = {name, quality, ilvl, sell, classID, bind}
 [1001]={'Green Shirt',2,18,50,4},[1002]={'Green Sword',2,26,300,2},[1003]={'Blue Helm',3,40,900,4},
 [11288]={'Greater Magic Wand',2,23,200,2},[1005]={'White Pants',1,18,40,4},[1006]={'Linen Cloth',1,5,10,7},
 [10940]={'Strange Dust',1,1,0,7},[10939]={'Greater Magic Essence',2,1,0,7},[10978]={'Small Glimmering Shard',2,1,0,7},
}
local function link(id) return '|cff1eff00|Hitem:'..id..'::::::::18:::::|h['..items[id][1]..']|h|r' end
local function stubItems()
 local oldInfo,oldItem=GetItemInfo,C_Item
 C_Item=nil
 GetItemInfo=function(x)
  local id=tonumber(type(x)=='number' and x or tostring(x):match('item:(%d+)'));local i=items[id]
  if not i then return oldInfo(x) end
  return i[1],link(id),i[2],i[3],1,'','',1,'INVTYPE_CHEST',1,i[4],i[5],0,i[6] or 2
 end
 return function() GetItemInfo,C_Item=oldInfo,oldItem end
end
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
 M.db.liveSeen={}
end
local function price(id,copper,age) M.db.liveSeen[id]={floor=copper,at=time()-(age or 0),quantity=100} end
local function tooltip() local t={lines={}}
 function t:AddDoubleLine(a,b) self.lines[#self.lines+1]=a..' = '..b end
 function t:AddLine(a) self.lines[#self.lines+1]=a end
 function t:text() return table.concat(self.lines,'\n') end
 return t end
local function run(fn,...) local restore={...};local ok,err=pcall(fn);for _,r in ipairs(restore) do r() end;if not ok then error(err,0) end end

check('1.11 Disenchant tables: uncommon, Forever weapon essence, rare shard, wands and whites excluded',function()
 reset()
 run(function()
  local t=M:DisenchantTable(M:DisenchantMeta(1001))
  assert(t[1].itemID==10940 and t[1].chance==0.75 and t[1].expected==0.75*2.5)
  assert(t[2].itemID==10939 and t[2].chance==0.20 and t[3].itemID==10978 and t[3].chance==0.05)
  local w=M:DisenchantTable(M:DisenchantMeta(1002))
  assert(w[1].itemID==11083 and w[1].chance==0.20 and w[2].itemID==10939 and w[2].chance==0.75,'weapons swap dust/essence; Forever gives Greater Magic Essence')
  local b=M:DisenchantTable(M:DisenchantMeta(1003));assert(#b==1 and b[1].itemID==11139 and b[1].chance==1)
  assert(not M:CanDisenchant(M:DisenchantMeta(11288)) and not M:CanDisenchant(M:DisenchantMeta(1005)) and not M:CanDisenchant(M:DisenchantMeta(1006)))
 end,stubItems())
end)

check('1.11 Advice compares disenchant (after AH cut) with vendor and the item on the AH',function()
 reset()
 run(function()
  price(10940,100);price(10939,300);price(10978,400)
  local a=M:DisenchantAdvice(link(1001))
  assert(a.canDisenchant and a.vendor==50 and a.missing==0)
  assert(a.disenchant==math.floor((0.75*2.5*100+0.2*1.5*300+0.05*400)*0.95),tostring(a.disenchant))
  assert(a.best.kind=='Disenchant' and a.second.kind=='Vendor')
  -- The item itself selling well on the AH beats both.
  M.db.liveSeen[M:LinkIdentity(link(1001))]={floor=2000,at=time()}
  a=M:DisenchantAdvice(link(1001));assert(a.best.kind=='Auction' and a.auction==1900)
  -- Cheap dust: vendor wins.
  reset();price(10940,5);price(10939,10);price(10978,10)
  a=M:DisenchantAdvice(link(1001));assert(a.best.kind=='Vendor' and a.disenchant<50)
  -- Missing material prices are flagged, not treated as zero silently.
  reset();price(10940,100)
  a=M:DisenchantAdvice(link(1001));assert(a.missing==2 and a.disenchant==math.floor(0.75*2.5*100*0.95))
 end,stubItems())
end)

check('1.11 Shift tooltip: materials with chance and value at current prices, total, best choice',function()
 reset()
 local oldShift=IsShiftKeyDown;local shift=false;IsShiftKeyDown=function() return shift end
 run(function()
  price(10940,100);price(10939,300);price(10978,400)
  local t=tooltip();M:AppendDisenchantTooltip(t,link(1001));assert(#t.lines==0,'nothing without Shift')
  shift=true
  t=tooltip();M:AppendDisenchantTooltip(t,link(1001));local x=t:text()
  assert(x:find('Disenchants into:',1,true))
  -- 75% x2-3 dust at 100c: 0.75*2.5*100*0.95 = 178c expected
  assert(x:find('Strange Dust 75% x2-3 = '..M:Coins(0.75*2.5*100*0.95),1,true),x)
  assert(x:find('Small Glimmering Shard 5% x1 = '..M:Coins(0.05*400*0.95),1,true))
  assert(x:find('Disenchant value = '..M:Coins(282),1,true))
  assert(x:find('Best = |cffb366ffDisenchant|r',1,true) and x:find('vs vendor',1,true))
  -- No material prices yet.
  reset();t=tooltip();M:AppendDisenchantTooltip(t,link(1001));assert(t:text():find('no material prices',1,true))
  -- Not for whites, and switchable.
  t=tooltip();M:AppendDisenchantTooltip(t,link(1005));assert(#t.lines==0)
  M.db.settings.tooltipDisenchant=false;t=tooltip();M:AppendDisenchantTooltip(t,link(1001));assert(#t.lines==0)
 end,stubItems(),function() IsShiftKeyDown=oldShift end)
end)

check('1.11 Within 10% of vendor (or below) defaults to Vendor, shown red',function()
 reset()
 local oldShift=IsShiftKeyDown;IsShiftKeyDown=function() return true end
 run(function()
  -- Green Shirt vendors for 50c. Dust only: 0.75*2.5*p*0.95 -> p=28 gives 49c, p=30 gives 53c (within 10%), p=40 gives 71c.
  price(10940,30)
  local a=M:DisenchantAdvice(link(1001));assert(a.disenchant==53 and a.deClose and a.best.kind=='Vendor' and a.second.kind=='Disenchant')
  local t=tooltip();M:AppendDisenchantTooltip(t,link(1001));local x=t:text()
  assert(x:find('Disenchant value = |cffff4040'..M:Coins(53),1,true) and x:find('Best = |cffff4040Vendor|r',1,true),x)
  price(10940,28);a=M:DisenchantAdvice(link(1001));assert(a.deClose and a.best.kind=='Vendor')
  price(10940,40);a=M:DisenchantAdvice(link(1001));assert(not a.deClose and a.best.kind=='Disenchant')
  -- The margin is a setting.
  M.db.settings.deVendorMargin=0.5;a=M:DisenchantAdvice(link(1001));assert(a.deClose and a.best.kind=='Vendor')
 end,stubItems(),function() IsShiftKeyDown=oldShift end)
end)

check('1.11 Your own disenchants are recorded and blended into the estimate',function()
 reset()
 local saved={GetNumLootItems,GetLootSlotLink,GetLootSlotInfo,C_Container}
 run(function()
  local meta=M:DisenchantMeta(1001)
  for _=1,10 do assert(M:RecordDisenchant(meta,{[10940]=3})) end
  assert(not M:RecordDisenchant(meta,{[2589]=1}),'non-material loot ignored')
  local y,n=M:DisenchantYields(meta);assert(n==10)
  assert(math.abs(y[1].expected-(0.75*2.5*10+30)/20)<1e-9 and math.abs(y[2].expected-0.3*10/20)<1e-9)
  -- Event chain: SENT (item name) -> SUCCEEDED -> loot window of materials.
  C_Container={GetContainerNumSlots=function(b) return b==0 and 1 or 0 end,
   GetContainerItemInfo=function() return {hyperlink=link(1001),iconFileID=1} end}
  GetNumLootItems=function() return 2 end
  GetLootSlotLink=function(i) return i==1 and link(10940) or link(10939) end
  GetLootSlotInfo=function(i) return nil,nil,i==1 and 2 or 1 end
  emit('UNIT_SPELLCAST_SENT','player','Green Shirt','cast-1',13262)
  emit('UNIT_SPELLCAST_SUCCEEDED','player','cast-1',13262)
  emit('LOOT_OPENED')
  local rec=VoidMarkMarketDB.disenchantLog[M:DisenchantBracket(meta)]
  assert(rec.n==11 and rec.mats[10940]==32 and rec.mats[10939]==1)
  -- A later ordinary loot window is not counted.
  emit('LOOT_OPENED');assert(rec.n==11)
 end,stubItems(),function() GetNumLootItems,GetLootSlotLink,GetLootSlotInfo,C_Container=saved[1],saved[2],saved[3],saved[4] end)
end)

check('1.11 Bag check window lists disenchantable gear, best first, with a total',function()
 reset()
 local oldC=C_Container
 run(function()
  price(10940,100);price(10939,300);price(10978,400);price(11139,5000)
  local bag={link(1005),link(1001),link(1003),link(1006)}
  C_Container={GetContainerNumSlots=function(b) return b==0 and #bag or 0 end,
   GetContainerItemInfo=function(_,s) return {hyperlink=bag[s],iconFileID=s} end}
  M:ShowDisenchantWindow()
  local f=M.disenchantWindow;assert(f:IsShown() and #f.data==2,'whites and cloth skipped')
  assert(f.rows[1].c[1]:GetText()==link(1003) and f.rows[1].c[5]:GetText():find('Disenchant',1,true))
  assert(f.rows[2].c[4]:GetText()==M:Coins(282) and not f.rows[3]:IsShown())
  local extra=(math.floor(5000*0.95)-900)+(282-50)
  assert(f.summary:GetText():find('Disenchant 2 of 2 items: about '..M:Coins(extra),1,true),f.summary:GetText())
  f:Hide()
 end,stubItems(),function() C_Container=oldC end)
end)

check('1.11 AH items mode reads the VoidMark market database: buy, disenchant, profit',function()
 reset()
 run(function()
  price(10940,100);price(10939,300);price(10978,400);price(11139,5000)
  M.db.market[1001]={marketKey=1001,itemID=1001,itemLink=link(1001),name='Green Shirt',quality=2,latest={floor=150},lastSeen=time()}
  M.db.market[1003]={marketKey=1003,itemID=1003,itemLink=link(1003),name='Blue Helm',quality=3,latest={floor=6000},lastSeen=time()}
  M.db.market[1005]={marketKey=1005,itemID=1005,itemLink=link(1005),name='White Pants',quality=1,latest={floor=1},lastSeen=time()}
  M.db.market[1007]={marketKey=1007,itemID=1007,name='Old',quality=2,latest={floor=1},lastSeen=time(),archived=true}
  M:ShowDisenchantWindow('market')
  local f=M.disenchantWindow;assert(#f.data==2,'only disenchantable, priced, live markets')
  assert(f.data[1].marketKey==1001 and f.data[1].advice.profit==282-150 and f.data[2].advice.profit==math.floor(5000*0.95)-6000)
  assert(f.heads[2]:GetText()=='Buy price' and f.rows[1].c[2]:GetText()==M:Coins(150) and f.rows[1].c[5]:GetText():find(M:Coins(132),1,true))
  assert(f.summary:GetText():find('1 of 2 disenchantable items in the VoidMark database',1,true),f.summary:GetText())
  f.bagsTab.scripts.OnClick(f.bagsTab);assert(f.mode=='bags' and f.heads[2]:GetText()=='Vendor')
  f:Hide()
 end,stubItems())
end)
end
