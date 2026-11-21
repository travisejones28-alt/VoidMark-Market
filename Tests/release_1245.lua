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
 local rn=M.RealmName; M.RealmName=function() return '' end -- no realm from any source
 VoidMarkMarketDB={economies={['TestRealm|Horde']={market={[14047]={name='Runecloth',lastSeen=time(),latest={floor=577,at=time()}}},syncPeer='voidmark bank'},['OtherRealm|Horde']={market={}}}}
 M.jobs={};M:InitializeDatabase();jobs()
 assert(M.economyID=='|Horde','setup: '..tostring(M.economyID))
 assert(M:RealmMissing())
 eq=eq or function(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
 assert(M:ReopenIfRealmArrived()==false,'reopened with no realm')
 GetNormalizedRealmName,GetRealmName=g,r; M.RealmName=rn
 assert(M:ReopenIfRealmArrived()==true,'did not reopen'); jobs()
 assert(M.economyID=='TestRealm|Horde',tostring(M.economyID))
 assert(M.db.market[14047] and M.db.market[14047].latest.floor==577,'Runecloth missing after reopen')
 assert(M.db.syncPeer=='voidmark bank','pairing lost')
 assert(VoidMarkMarketDB.economies['|Horde']==nil,'blank copy left')
 assert(M:ReopenIfRealmArrived()==false,'reopened twice')
end)
check('1.23.47 Reconnect reopens real data when the realm arrived, and always says what happened',function()
 local g,r,pr=GetNormalizedRealmName,GetRealmName,M.Print
 local said={}; M.Print=function(_,t) said[#said+1]=t end
 GetNormalizedRealmName=function() return '' end; GetRealmName=function() return '' end
 local rn=M.RealmName; M.RealmName=function() return '' end -- no realm from any source
 VoidMarkMarketDB={economies={['TestRealm|Horde']={market={},syncPeer='voidmark bank-testrealm'},['OtherRealm|Horde']={market={}}}}
 M.jobs={};M:InitializeDatabase();jobs()
 M:ReconnectSharing(false)
 assert(said[#said]:find('realm name yet',1,true),tostring(said[#said]))
 GetNormalizedRealmName,GetRealmName=g,r; M.RealmName=rn; said={}
 M:ReconnectSharing(false); jobs()
 assert(M.economyID=='TestRealm|Horde',tostring(M.economyID))
 assert(said[1]:find('reopened',1,true),tostring(said[1]))
 assert(said[#said]:find('reconnecting to voidmark bank',1,true),tostring(said[#said]))
 M.Print=pr
end)
check('1.23.48 realm name empty all session: saved realm used (server, character, only realm)',function()
 local g,r,gu=GetNormalizedRealmName,GetRealmName,UnitGUID
 UnitGUID=function() return 'Player-5150-0ABC' end
 -- Learn while the game still gives the name.
 VoidMarkMarketDB={economies={['TestRealm|Horde']={market={[14047]={name='Runecloth',lastSeen=time(),latest={floor=577,at=time()}}},syncPeer='voidmark bank-testrealm'},['OtherRealm|Horde']={market={}}}}
 M.jobs={};M:InitializeDatabase();jobs()
 assert(VoidMarkMarketDB.realmByServer['5150']=='TestRealm')
 -- Now the game gives nothing, all session.
 GetNormalizedRealmName=function() return '' end; GetRealmName=function() return '' end
 M.jobs={};M:InitializeDatabase();jobs()
 assert(M.economyID=='TestRealm|Horde',tostring(M.economyID)); assert(M.realmSource=='server 5150',M.realmSource)
 assert(M.db.market[14047],'prices'); assert(M.db.syncPeer=='voidmark bank-testrealm','pairing')
 -- No server match: last realm for this character.
 UnitGUID=function() return 'Player-9999-0ABC' end
 M.jobs={};M:InitializeDatabase();jobs()
 assert(M.economyID=='TestRealm|Horde',tostring(M.economyID)); assert(M.realmSource=='last used',M.realmSource)
 -- Nothing remembered: the saved realm.
 VoidMarkMarketDB={economies={['TestRealm|Horde']={market={}}}}
 M.jobs={};M:InitializeDatabase();jobs()
 assert(M.economyID=='TestRealm|Horde',tostring(M.economyID)); assert(M.realmSource=='saved realm',M.realmSource)
 -- Two Horde realms saved (Soulreaver's account): the paired one wins.
 VoidMarkMarketDB={economies={['Realm7PvE|Horde']={market={[1]={},[2]={},[3]={}}},['TestRealm|Horde']={market={},syncPeer='voidmark bank-testrealm'},['Realm3PvE|Alliance']={market={}}}}
 M.jobs={};M:InitializeDatabase();jobs()
 assert(M.economyID=='TestRealm|Horde',tostring(M.economyID))
 GetNormalizedRealmName,GetRealmName,UnitGUID=g,r,gu
end)
check('1.23.49 surname is never a realm; data saved as Soulreaver|Horde merged back',function()
 local g,r,un,uf=GetNormalizedRealmName,GetRealmName,UnitName,UnitFullName
 GetNormalizedRealmName=function() return '' end; GetRealmName=function() return '' end
 UnitName=function() return 'Voidmark','Soulreaver' end; UnitFullName=function() return 'Voidmark','Soulreaver' end
 VoidMarkMarketDB={realmByServer={['5150']='Soulreaver'},realmByCharacter={Voidmark='Soulreaver'},
  economies={['TestRealm|Horde']={market={[14047]={name='Runecloth',lastSeen=time()-100,latest={floor=577,at=time()-100}}},syncPeer='voidmark bank-testrealm'},
  ['Soulreaver|Horde']={market={[2589]={name='Linen Cloth',lastSeen=time(),latest={floor=30,at=time()}}}}}}
 M.jobs={};M:InitializeDatabase();jobs()
 assert(M.economyID=='TestRealm|Horde',tostring(M.economyID))
 assert(VoidMarkMarketDB.economies['Soulreaver|Horde']==nil,'surname copy left')
 assert(M.db.market[2589] and M.db.market[14047],'prices lost')
 assert(M.db.syncPeer=='voidmark bank-testrealm')
 GetNormalizedRealmName,GetRealmName,UnitName,UnitFullName=g,r,un,uf
end)
end
