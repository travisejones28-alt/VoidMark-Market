return function(M,check,jobs,advance,emit)
-- 1.9.8 Green flips.
local function reset()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M.shareRun={};M:InitializeDatabase();jobs()
 M.ahOpen=true;M:CancelRequests('test');M.queue.waiting={};M.queue.dedupe={};M.queue.active=nil
 M.execution={state='idle',message='idle'};M.selectedRow=nil;M.flipRows=nil;M.flipBuiltFor=nil
 M:InitializeUI()
end
local NOW=1000000
local function market(key,name,o)
 o=o or {}
 local m={marketKey=key,itemID=o.itemID or 1000+key,itemSuffix=o.suffix or 5,name=o.base or name,quality=o.quality or 2,
  itemLink='|cff1eff00|Hitem:'..(1000+key)..'::::::'..(o.suffix or 5)..'|h['..name..']|h|r',vendorPrice=o.vendor or 100,
  lastSeen=o.seen or NOW,latest={floor=o.floor or 1200,second=o.second,listings=o.listings or 2}}
 M.db.market[key]=m
 return m
end
local function keys(rows) local out={};for _,r in ipairs(rows) do out[#out+1]=r.name end;return table.concat(out,'|') end

check('1.9.8 Green flips pick cheap good-suffix greens and price them under the next listing',function()
 reset()
 market(1,'Bloodspattered Sash of the Tiger',{floor=1200,second=4000})
 market(2,'Willow Vest of Intellect',{floor=900,second=nil,listings=1})            -- only listing: 35s guess
 market(3,'Heavy Shortbow of the Bear',{floor=500,second=4000})                     -- suffix not wanted
 market(4,'Feral Bindings of Healing',{floor=1200,second=4000,quality=3})           -- not a green
 market(5,'Dervish Spaulders of Healing',{floor=2500,second=9000})                   -- above 15s max buy
 market(6,'Buccaneer\'s Bracers of Intellect',{floor=1000,second=1000})             -- another at the same price
 market(7,'Old Sash of Agility',{floor=1000,second=5000,seen=NOW-3600})             -- not in the latest scan
 market(8,'Cheap Belt of Magic',{floor=1400,second=1900})                            -- profit below 10s
 market(9,'Pre-update Gloves of the Tiger',{floor=800,listings=3})                     -- old scan: next price unknown
 local rows=M:BuildFlipRows()
 assert(keys(rows)=='Bloodspattered Sash of the Tiger|Willow Vest of Intellect','most profit first, got '..keys(rows))
 local tiger=rows[1]
 assert(tiger.sell==3900,'whole silver under the next listing (40s -> 39s)')
 assert(tiger.profit==math.floor(3900*0.95)-1200-15,'profit after 5% cut and deposit estimate, got '..tiger.profit)
 local vest=rows[2]
 assert(vest.guess and vest.sell==3500 and vest.profit==math.floor(3500*0.95)-900-15)
end)

check('1.9.8 Flip settings: max buy, min profit and suffix list apply from the screen',function()
 reset();M:SetView('flips');M:RenderUI()
 market(1,'Dervish Spaulders of Healing',{floor=2500,second=9000})
 market(2,'Sash of the Monkey',{floor=1000,second=5000})
 M.flipScreen.maxBuy:SetText('30');M.flipScreen.minProfit:SetText('10');M.flipScreen.words:SetText('Monkey')
 M:ApplyFlipSettings()
 assert(M.db.settings.flipMaxBuy==3000 and M.db.settings.flipMinProfit==1000 and M.db.settings.flipWords=='Monkey')
 assert(keys(M:FlipRows())=='Sash of the Monkey','suffix filter applied')
 M.db.settings.flipWords='Healing,Monkey'
 assert(keys(M:FlipRows())=='Dervish Spaulders of Healing|Sash of the Monkey','rows rebuild when settings change')
end)

check('1.9.8 Flips screen lists rows and double-click opens the normal Buy flow',function()
 reset()
 market(1,'Bloodspattered Sash of the Tiger',{floor=1200,second=4000})
 M:SetView('flips');M:RenderUI()
 assert(M.flipScreen:IsShown() and M.flipScreen.rows[1]:IsShown() and not M.flipScreen.rows[2]:IsShown())
 local r=M.flipScreen.rows[1]
 assert(r.c[2]:GetText():find('Bloodspattered Sash of the Tiger',1,true))
 local picked;local old=M.SelectOpportunity;M.SelectOpportunity=function(_,o) picked=o end
 r.scripts.OnDoubleClick(r)
 M.SelectOpportunity=old
 assert(picked and picked.kind=='shopping' and picked.marketKey==1,'buys through the Shopping purchase path')
end)

check('1.9.8 Scan observation records the next price above the lowest',function()
 reset()
 local g={itemID=5,listings=3,quantity=3,floorUnitPrice=1000,ceilingUnitPrice=5000,priceLevels={[1000]=1,[3000]=1,[5000]=1}}
 assert(M:BuildMarketObservation(g,1,NOW).second==3000)
 g.priceLevels={[1000]=2,[5000]=1}
 assert(M:BuildMarketObservation(g,1,NOW).second==1000,'two at the lowest price: next is the same price')
 g={itemID=5,listings=1,quantity=1,floorUnitPrice=1000,ceilingUnitPrice=1000,priceLevels={[1000]=1}}
 assert(M:BuildMarketObservation(g,1,NOW).second==nil,'single listing has no next price')
end)
end
