return function(M,check,jobs,advance,emit)
check('1.23.45 an empty realm name at load never sends prices to an empty "|Horde" copy',function()
 local g=GetNormalizedRealmName
 GetNormalizedRealmName=function() return '' end
 VoidMarkMarketDB={economies={['TestRealm|Horde']={market={[14047]={name='Runecloth',lastSeen=time(),latest={floor=511,at=time()}}}}}}
 M.jobs={};M:InitializeDatabase();jobs()
 assert(M.economyID~='|Horde','realm was blank: '..tostring(M.economyID))
 assert(M.db.market[14047] and M.db.market[14047].latest.floor==511,'Runecloth price not found')
 -- A copy already saved under the blank realm is folded back in.
 GetNormalizedRealmName=g
 VoidMarkMarketDB={economies={['TestRealm|Horde']={market={}},['|Horde']={market={[2589]={name='Linen Cloth',lastSeen=time(),latest={floor=10,at=time()}}}}}}
 M.jobs={};M:InitializeDatabase();jobs()
 assert(VoidMarkMarketDB.economies['|Horde']==nil,'blank-realm copy left behind')
 assert(M.db.market[2589],'blank-realm prices lost')
end)
check('1.23.46 both realm names empty at load: real data reopened when the realm arrives',function()
 local g,r=GetNormalizedRealmName,GetRealmName
 GetNormalizedRealmName=function() return '' end; GetRealmName=function() return '' end
 VoidMarkMarketDB={economies={['TestRealm|Horde']={market={[14047]={name='Runecloth',lastSeen=time(),latest={floor=577,at=time()}}},syncPeer='voidmark bank'}}}
 M.jobs={};M:InitializeDatabase();jobs()
 assert(M.economyID=='|Horde','setup: '..tostring(M.economyID))
 assert(M:RealmMissing())
 eq=eq or function(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
 assert(M:ReopenIfRealmArrived()==false,'reopened with no realm')
 GetNormalizedRealmName,GetRealmName=g,r
 assert(M:ReopenIfRealmArrived()==true,'did not reopen'); jobs()
 assert(M.economyID=='TestRealm|Horde',tostring(M.economyID))
 assert(M.db.market[14047] and M.db.market[14047].latest.floor==577,'Runecloth missing after reopen')
 assert(M.db.syncPeer=='voidmark bank','pairing lost')
 assert(VoidMarkMarketDB.economies['|Horde']==nil,'blank copy left')
 assert(M:ReopenIfRealmArrived()==false,'reopened twice')
end)
end
