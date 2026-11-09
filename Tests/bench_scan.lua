return function(M,check,jobs,advance,emit,freshScan)
-- Full-scan throughput with a real clock: frames needed for 25,000 auctions /
-- 5,000 items on top of 8,000 stored markets. One RunJobs call = one frame.
check('BENCH full scan frames (25k auctions, 5k items, 8k stored)',function()
 local fake=debugprofilestop
 local t0=os.clock()
 debugprofilestop=function() return (os.clock()-t0)*1000 end
 local info,link=C_AuctionHouse.GetReplicateItemInfo,C_AuctionHouse.GetReplicateItemLink
 C_AuctionHouse.GetReplicateItemInfo=function(i)
  local id=i%5000+1
  return 'Item '..id,999,1+i%20,1,true,1,0,0,0,(id*37%9000+100)*(1+i%3),0,false,nil,'Other','Other-TestRealm',0,id,true
 end
 C_AuctionHouse.GetReplicateItemLink=function(i) return '|Hitem:'..(i%5000+1)..':0:0:0:0:0:0:0|h[Item]|h' end
 for k=20001,23000 do M.db.market[k]={marketKey=k,itemID=k,name='Old '..k,latest={floor=100,quantity=1,listings=1},history={},lastSeen=1} end
 freshScan(25000);emit('REPLICATE_ITEM_LIST_UPDATE')
 local frames,worst=0,0
 local phases={}
 while next(M.jobs) do
  local s=os.clock();M:RunJobs();local spent=(os.clock()-s)*1000
  frames=frames+1;worst=math.max(worst,spent)
  local p=M.scanState.phase or '?'
  if p=='done' then for id in pairs(M.jobs) do p='after:'..id end end
  phases[p]=(phases[p] or 0)+1
  assert(frames<100000,'stuck')
 end
 local parts={};for p,n in pairs(phases) do parts[#parts+1]=p..'='..n end;table.sort(parts)
 print(string.format('BENCH scan: %d frames (%.1fs at 60fps, %.1fs at 30fps), worst frame %.1fms, cpu %.2fs | %s',
  frames,frames/60,frames/30,worst,os.clock()-t0,table.concat(parts,' ')))
 assert(M.scanState.phase=='done')
 for k=20001,23000 do M.db.market[k]=nil end
 C_AuctionHouse.GetReplicateItemInfo,C_AuctionHouse.GetReplicateItemLink=info,link
 debugprofilestop=fake
end)
end
