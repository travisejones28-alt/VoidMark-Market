return function(M,check,jobs,advance,emit)
-- 1.11.4 Faster scan processing; Selling never sticks on a moved bag item;
-- interactive jobs are not starved by background ones.

check('1.11.4 Scan skips per-row link work for plain items and resolves each gear variant once',function()
 local oldA=C_AuctionHouse;local oldI,oldD=GetItemInfoInstant,GetDetailedItemLevelInfo;local oldItem=C_Item
 local api=setmetatable({},{__index=oldA});C_AuctionHouse=api;C_Item=nil
 local links,ident=0,0;local oldLI=M.LinkIdentity
 M.LinkIdentity=function(self,...) ident=ident+1;return oldLI(self,...) end
 local ok,err=pcall(function()
  -- 300 rows: items 101-105 are trade goods, 201-203 are gear (two suffixes each).
  local N=300
  local function id(i) return i%2==0 and (101+i%5) or (201+i%3) end
  api.GetNumReplicateItems=function() return N end
  api.GetReplicateItemInfo=function(i)
   return 'Item',1,1,2,true,1,0,0,0,1000+i,0,false,nil,'Other','Other-TestRealm',0,id(i),true
  end
  api.GetReplicateItemLink=function(i)
   links=links+1;local x=id(i)
   if x>200 then return '|cff1eff00|Hitem:'..x..':'..(i%7)..':::::'..(500+math.floor(i/2)%2)..':'..(90000+i)..':25:::::|h[Gear]|h|r' end
   return '|cffffffff|Hitem:'..x..'::::::::25:::::|h[Goods]|h|r'
  end
  GetItemInfoInstant=function(x) local n=tonumber(x) or tonumber(tostring(x):match('item:(%d+)'));return n,'','',n>200 and 'INVTYPE_CHEST' or '' end
  GetDetailedItemLevelInfo=function() return 20 end
  M.ahOpen=true;M.jobs={}
  M:StartSnapshotProcessing(N,'test')
  jobs()
  -- Gear rows (150) read their link; plain items read it once each (5).
  assert(links==150+5,'link calls '..links)
  -- 3 gear items x 2 suffixes = 6 variants resolved, not 150 rows.
  assert(ident==6,'identity resolves '..ident)
  for x=101,105 do assert(M.db.market[x] and M.db.market[x].itemLink:find('item:'..x,1,true),'plain market '..x) end
  for x=201,203 do for _,s in ipairs({500,501}) do assert(M.db.market[M:Key(x,s,20,0)],'gear variant '..x..':'..s) end end
  assert(M.db.latestScan.auctionsProcessed==N)
 end)
 C_AuctionHouse=oldA;GetItemInfoInstant,GetDetailedItemLevelInfo=oldI,oldD;C_Item=oldItem;M.LinkIdentity=oldLI
 if not ok then error(err,0) end
end)

check('1.11.4 Selling finds an item that moved slots instead of failing; locked retries quickly',function()
 local oldA,oldL,oldC=C_AuctionHouse,ItemLocation,C_Container
 local api=setmetatable({},{__index=oldA});C_AuctionHouse=api
 local ok,err=pcall(function()
  local link='|cffffffff|Hitem:2589::::::::25:::::|h[Linen Cloth]|h|r'
  local bag={}
  C_Container={GetContainerNumSlots=function(b) return b==0 and 4 or 0 end,
   GetContainerItemInfo=function(b,s) return b==0 and bag[s] or nil end}
  ItemLocation={CreateFromBagAndSlot=function(_,b,s) return {bag=b,slot=s} end}
  api.IsThrottledMessageSystemReady=function() return true end
  api.GetItemKeyFromItem=function(loc) local i=bag[loc.slot];return i and {itemID=i.itemID,itemSuffix=0,itemLevel=0,battlePetSpeciesID=0} end
  api.GetItemKeyInfo=function() return {isCommodity=true} end
  api.GetAvailablePostCount=function() return 20 end
  M.ahOpen=true;M.sellingRows={};M.bagsDirty=false
  local row={bag=0,slot=1,itemID=2589,itemLink=link,marketKey=2589,quantity=20}
  -- The list says slot 1, the cloth is now in slot 3.
  bag[3]={itemID=2589,hyperlink=link,stackCount=20}
  local b,e=M:ReadBagSlot(row)
  assert(b and row.slot==3 and M.bagsDirty,'relocated: '..tostring(e))
  -- Gone entirely.
  bag[3]=nil;b,e=M:ReadBagSlot(row);assert(not b and e:find('no longer in your bags',1,true))
  -- Locked right after a post: quick retries, no error printed.
  bag[3]={itemID=2589,hyperlink=link,stackCount=20,isLocked=true}
  local printed;local oldPrint=M.Print;M.Print=function(_,m) printed=m end
  M.view='selling';M.selectedRow=row;M.sellRetry=nil
  M:CheckPost(row);M.Print=oldPrint
  assert(not printed and M.sellCheckRow==row and M.sellCheckAt-GetTime()<=0.21,'retry soon')
  M.sellCheckAt=nil;M.sellCheckRow=nil;M.sellRetry=nil;M.postQuote=nil
 end)
 C_AuctionHouse,ItemLocation,C_Container=oldA,oldL,oldC
 if not ok then error(err,0) end
end)

check('1.11.4 Bag list and price-check jobs run before a long background job; background jobs take turns',function()
 local saved=M.jobs;M.jobs={}
 local ran={}
 local function hog(name) return function(start) ran[name]=(ran[name] or 0)+1;while debugprofilestop()-start<M.budget do end;return false end end
 M:AddJob('scan',hog('scan'));M:AddJob('model',hog('model'))
 M:AddJob('bags',function() ran.bags=true;return true end)
 M:RunJobs()
 assert(ran.bags,'bags ran first')
 M:RunJobs()
 assert(ran.scan==1 and ran.model==1,'background jobs alternate')
 M.jobs=saved
end)
end
