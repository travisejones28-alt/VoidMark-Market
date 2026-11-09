return function(M,check,jobs,advance,emit,freshScan)
-- 1.9.13 compact price history.
check('1.9.13 history stores only the fields it needs; latest keeps the full snapshot',function()
 freshScan(300);emit('REPLICATE_ITEM_LIST_UPDATE');jobs()
 local m=M.db.market[5];assert(m and m.latest and m.latest.q10~=nil)
 local h=m.history[#m.history];assert(h.median and h.at and h.quantity and h.floor and h.q10==nil and h.tiers==nil)
 local n=0;for _ in pairs(h) do n=n+1 end;assert(n<=#M.HistoryFields)
end)
check('1.9.13 history saved by older versions is shrunk once at login without losing prices',function()
 local m=M.db.market[5]
 local old={at=m.history[1].at,median=777,depthValue=700,quantity=9,floor=650,listings=3,q10=600,q25=640,q75=800,q90=900,tiers=4,ceiling=950,spreadRatio=1.5,cheapQuantity=0,cheapCost=0,scanID=1,second=651,floorQuantity=1,meaningfulFloor=600}
 table.insert(m.history,1,old);M.db.historyFormat=nil
 M:InitializeDatabase();jobs()
 local h=m.history[1];assert(h.q10==nil and h.median==777 and h.floor==650 and h.at==old.at)
 assert(M.db.historyFormat==2)
 table.remove(m.history,1)
end)
check('MEM 1.9.13 memory after 6 scans of 5,000 items',function()
 local info,link=C_AuctionHouse.GetReplicateItemInfo,C_AuctionHouse.GetReplicateItemLink
 C_AuctionHouse.GetReplicateItemInfo=function(i) local id=i%5000+1
  return 'Item '..id,999,1+i%20,1,true,1,0,0,0,(id*37%9000+100)*(1+i%3)+i%7,0,false,nil,'Other','Other-TestRealm',0,id,true end
 C_AuctionHouse.GetReplicateItemLink=function(i) return '|Hitem:'..(i%5000+1)..':0:0:0:0:0:0:0|h[Item]|h' end
 local function mem() collectgarbage('collect');collectgarbage('collect');return collectgarbage('count')/1024 end
 local first
 for n=1,6 do freshScan(25000);emit('REPLICATE_ITEM_LIST_UPDATE');jobs();advance(1000);if n==1 then first=mem() end end
 local per=(mem()-first)/5
 print(string.format('MEM per scan of 5,000 items: %.1f MB (was ~6.5 MB before 1.9.13)',per))
 assert(per<3,'history growth per scan too large: '..per)
 for k=1,5000 do M.db.market[k]=nil end
 C_AuctionHouse.GetReplicateItemInfo,C_AuctionHouse.GetReplicateItemLink=info,link
end)
end
