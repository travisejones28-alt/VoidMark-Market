return function(M,check,jobs,advance,emit,freshScan)
-- 1.9.12 faster full-scan processing.
check('1.9.12 scans get a larger frame budget only while scanning at the AH, out of combat',function()
 local combat=InCombatLockdown
 M.scanState.running=false;assert(M:FrameBudget()==4)
 M.scanState.running=true;M.ahOpen=true;M.db.settings.scanSpeed=nil;assert(M:FrameBudget()==12)
 M.db.settings.scanSpeed='smooth';assert(M:FrameBudget()==4)
 InCombatLockdown=function() return true end;M.db.settings.scanSpeed='fast';assert(M:FrameBudget()==4)
 InCombatLockdown=combat;M.ahOpen=false;assert(M:FrameBudget()==4)
 SlashCmdList.VOIDMARKMARKET('scanspeed normal');assert(M.db.settings.scanSpeed=='normal')
 SlashCmdList.VOIDMARKMARKET('scanspeed bogus');assert(M.db.settings.scanSpeed=='normal')
 M.db.settings.scanSpeed=nil;M.scanState.running=false
end)
check('1.9.12 player identity is read once per scan, missing items are requested, timing is reported',function()
 local unit,item,link=UnitName,C_Item,C_AuctionHouse.GetReplicateItemLink
 local names,loads=0,{}
 UnitName=function() names=names+1;return 'Tester' end
 C_Item=setmetatable({RequestLoadItemDataByID=function(id) loads[#loads+1]=id end},{__index=item})
 C_AuctionHouse.GetReplicateItemLink=function(i) if i~=3 then return link(i) end end
 local printed
 local print_=M.Print;M.Print=function(_,s) printed=s end
 freshScan(400);advance(4);emit('REPLICATE_ITEM_LIST_UPDATE');jobs(0.25)
 M.Print=print_
 assert(names<=3,'UnitName per row: '..names)
 assert(#loads==1 and loads[1]==4,'deferred item data requested once')
 local s=M.db.latestScan;assert(s.processingMS and s.timing:find('server 4s',1,true) and s.timing:find('processing',1,true))
 assert(printed and printed:find('Scan complete',1,true))
 UnitName,C_Item,C_AuctionHouse.GetReplicateItemLink=unit,item,link
end)
end
