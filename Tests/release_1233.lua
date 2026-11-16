return function(M,check,jobs,advance,emit)
check('1.23.33 "pricecheck [item]" in guild/party/whisper is answered with the last scan price',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 local sent={};SendChatMessage=function(t,ch,_,to) sent[#sent+1]={t,ch,to} end
 local oldTimer=C_Timer;C_Timer=nil
 M.priceCheck.pending={};M.priceCheck.answered={};M.priceCheck.sent={}
 local link='|cff1eff00|Hitem:91233::::::::60:::::::|h[Test Blade]|h|r'
 local key=M:LinkIdentity(link);assert(key~=nil,'link key')
 M.db.market[key]={marketKey=key,itemID=91233,name='Test Blade',lastSeen=time()-7200,latest={floor=123456},observations=1}
 M.db.latestScan={completedAt=time()-7200}
 assert(M:PlainCoins(123456)=='12g 34s 56c' and M:PlainCoins(500)=='5s' and M:PlainCoins(0)=='0c')
 assert(M:IsPriceCheckAsk('pricecheck '..link) and M:IsPriceCheckAsk('Price Check '..link..' please') and M:IsPriceCheckAsk('pc '..link))
 assert(not M:IsPriceCheckAsk('selling '..link) and not M:IsPriceCheckAsk('pricecheck nothing linked') and not M:IsPriceCheckAsk('VoidMark price: '..link..' 1g'))
 -- Whisper: answered at once to the asker.
 emit('CHAT_MSG_WHISPER','pricecheck '..link,'Some Friend')
 assert(#sent==1 and sent[1][2]=='WHISPER' and sent[1][3]=='Some Friend','whisper not answered')
 assert(sent[1][1]=='VoidMark price: '..link..' 12g 34s 56c (scanned 2h ago)',sent[1][1])
 -- Guild: answered after a short wait.
 emit('CHAT_MSG_GUILD','pricecheck '..link,'Some Friend')
 assert(#sent==1,'guild answered without waiting');advance(5);M:PriceCheckFlush()
 assert(#sent==2 and sent[2][2]=='GUILD','guild not answered')
 -- Asked again within 30s: no second answer.
 emit('CHAT_MSG_GUILD','pricecheck '..link,'Other Guy');advance(5);M:PriceCheckFlush()
 assert(#sent==2,'repeat answered')
 -- Party: another client answers first, so we stay quiet.
 emit('CHAT_MSG_PARTY','pc '..link,'Some Friend')
 emit('CHAT_MSG_PARTY','VoidMark price: '..link..' 12g','Voidmark Bank')
 advance(5);M:PriceCheckFlush();assert(#sent==2,'double answer in party')
 -- Switched off: silent.
 M.db.settings.priceCheckWhisper=false;advance(60)
 emit('CHAT_MSG_WHISPER','pricecheck '..link,'Some Friend');assert(#sent==2,'answered while off')
 M.db.settings.priceCheckWhisper=nil
 -- No data: says so.
 emit('CHAT_MSG_WHISPER','pricecheck |cffffffff|Hitem:91234::::::::60:::::::|h[Nothing]|h|r','Some Friend')
 assert(#sent==3 and sent[3][1]:find('no scan data',1,true),'no-data reply')
 SendChatMessage=nil;C_Timer=oldTimer
end)
end
