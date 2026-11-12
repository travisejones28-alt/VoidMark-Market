return function(M,check,jobs,advance,emit)
check('1.13.1 Cancelling shows inbound gold from sold auctions and the value still listed',function()
 local oldRows=M.ownedRows
 M:SetView('my auctions');M.ahOpen=true
 local k={itemID=1}
 M.ownedRows={
  {auctionID=1,itemKey=k,name='Heavy Leather',quantity=30,unit=208,status=1,timeLeft=3300},   -- 6240
  {auctionID=2,itemKey=k,name='Medium Hide',quantity=6,unit=197,status=1,timeLeft=3060},      -- 1182, sooner
  {auctionID=3,itemKey=k,name='Rosecap',quantity=2,unit=1649,timeLeft=6720},                  -- listed 3298
  {auctionID=4,itemKey=k,name='Broken',quantity=nil,unit=50,status=1}}                         -- ignored
 local sold,soldN,listed,listedN,nextIn=M:InboundGold()
 assert(sold==math.floor(7422*0.95) and soldN==2,'sold '..sold)
 assert(listed==math.floor(3298*0.95) and listedN==1,'listed '..listed)
 assert(nextIn==3060,'next mail')
 M:RenderUI();local t=M.cancelScreen.inbound:GetText()
 assert(t:find('Inbound:',1,true) and t:find(M:Coins(sold),1,true) and t:find('2 sold',1,true) and t:find('next mail 51m',1,true),t)
 assert(t:find('Listed:',1,true) and t:find(M:Coins(listed),1,true) and t:find('5% AH cut',1,true),t)
 M.ownedRows={};M:RenderUI();assert(M.cancelScreen.inbound:GetText()=='','empty when nothing up')
 M.ownedRows=oldRows
end)
end
