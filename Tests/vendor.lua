local M={db={market={},settings={},lastDepthSnapshotAt=100}}
function M:Finite(n,lo,hi) return type(n)=='number' and n>=lo and n<=hi end
function M:Economics(m,c,q,k) return {cost=c,quantity=q,net=m.vendorPrice*q-c,kind=k} end
function M:CheckRisk() return false,{'Minimum profit'} end
function M:MarketFresh(m) return m.lastSeen==100 end
assert(loadfile('Vendor.lua'))('VoidMarkMarket',M)
local function market(id,lots)
 local m={marketKey=id,itemID=id,name='Item '..id,vendorPrice=100,lastSeen=100,depth={at=100,lots=lots}}
 M.db.market[id]=m;return m
end
market(1,{{quantity=20,cost=1999,count=2},{quantity=1,cost=100,count=1},{quantity=1,cost=101,count=1}})
market(2,{{quantity=1,cost=50,count=3}})
local stale=market(3,{{quantity=1,cost=1,count=1}});stale.lastSeen=99
market(4,{}) -- own listings do not enter acquisition depth
local rows=M:GetVendorRows('')
assert(#rows==2 and rows[1].itemID==2 and rows[1].totalProfit==150)
assert(rows[2].quantity==40 and rows[2].totalCost==3998 and rows[2].totalProfit==2)
assert(not rows[2].pass and rows[2].buyQuantity==20) -- small blocked deals remain visible
assert(#M:GetVendorRows('item 1')==1 and #M:GetVendorRows('2')==1)
assert(#M:GetVendorRows('nothing')==0)
M.db.market[1].depth.incomplete=true
assert(M:GetVendorRows('1')[1].status=='Partial depth')
M.db.market[1].cacheUntrusted=true;assert(#M:GetVendorRows('1')==0)
print('PASS Vendor: whole stacks, equality excluded, profit sorting, small deals, freshness, own lots, filtering, partial depth')
