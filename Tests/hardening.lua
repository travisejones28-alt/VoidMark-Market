-- Loaded by the main regression file with its deterministic client helpers.
local M,check,mk,jobs=...
check('Malformed auction identities never compare equal or produce NaN table keys',function()
 assert(M:Key(0/0)==nil);assert(M:Key(math.huge)==nil);assert(M:Key(1.5)==nil)
 assert(M:Key(12,'not a suffix')==nil);assert(not M:SameKey({},{}))
 assert(M:SameKey({itemID=12,itemSuffix=-5},{itemID=12,itemSuffix=-5}))
 assert(not M:SameKey({itemID=12,itemSuffix=-5},{itemID=12,itemSuffix=0}))
end)
check('Future market timestamps fail the resale risk freshness gate',function()
 local market=mk();local at=market.lastSeen
 market.lastSeen=time()+86400
 local pass,why=M:CheckRisk(market,M:Economics(market,500,1,'resale'))
 assert(not pass);assert(table.concat(why,' '):find('timestamp',1,true))
 market.lastSeen=at
end)
check('Malformed invoice amounts cannot alter inventory basis or book profit',function()
 local market=mk();local key=M:InventoryKey(market.marketKey)
 M.db.inventory[key]={quantity=1,cost=100,marketKey=market.marketKey,character=M.characterID}
 local entry={kind='mail sale',character=M.characterID,marketKey=market.marketKey,invoiceVerified=true,quantity=1,gross=200,fee=-1}
 assert(not M:BookSale(entry));assert(M.db.inventory[key].quantity==1 and not entry.booked)
 entry.fee=nil;assert(not M:BookSale(entry));entry.fee=10;entry.quantity=0/0
 assert(not M:BookSale(entry));assert(M.db.inventory[key].cost==100)
end)
check('Unmodeled saved markets do not crash the selling inventory reader',function()
 local old=C_Container;local key=999888
 M.db.market[key]={itemID=key,name='Incomplete legacy data',latest={floor=10}}
 C_Container={GetContainerNumSlots=function(bag) return bag==0 and 1 or 0 end,
  GetContainerItemInfo=function() return {itemID=key,stackCount=1,hyperlink='|Hitem:999888:0:0:0:0:0:0|h[Test]|h'} end}
 local errors=#M.runtimeLog;M:RefreshInventory();jobs()
 for i=errors+1,#M.runtimeLog do assert(M.runtimeLog[i].kind~='JOB ERROR') end
 M.db.market[key]=nil;C_Container=old
end)

check('Non-finite display amounts cannot crash financial panels',function()
 assert(M:Money(0/0)=='Unknown' and M:Money(math.huge)=='Unknown')
end)
