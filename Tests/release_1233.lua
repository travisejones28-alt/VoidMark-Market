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
check('1.23.33 TSM prices fill in when Market has none or only an old one; replies are paced and secret chat is ignored',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 local sent={};SendChatMessage=function(t,ch,_,to) sent[#sent+1]={t,ch,to} end
 local oldTimer=C_Timer;C_Timer=nil
 M.priceCheck.pending={};M.priceCheck.answered={};M.priceCheck.sent={};M.priceCheck.lastSend=nil
 assert(M:TSMPrice('|Hitem:5|h[X]|h')==nil,'no TSM installed')
 TSM_API={GetCustomPriceValue=function(src,item)
  if item=='i:91240' and src=='DBMinBuyout' then return 4200 end
  if item=='i:91241' and src=='DBMarket' then return 9900 end
  if item=='i:91242' then return 5000 end
 end}
 assert(M:TSMPrice('|cffffffff|Hitem:91241::::::::60:::::::|h[B]|h|r')==9900,'DBMarket fallback')
 local a='|cffffffff|Hitem:91240::::::::60:::::::|h[Alpha]|h|r'
 local t1,has=M:PriceCheckReply(a)
 assert(has and t1=='VoidMark price: '..a..' 42s (TSM)',t1)
 -- Our price from 2 days ago: TSM's wins in the reply.
 local b='|cffffffff|Hitem:91242::::::::60:::::::|h[Beta]|h|r';local k=M:LinkIdentity(b)
 M.db.market[k]={marketKey=k,itemID=91242,name='Beta',lastSeen=time()-2*86400,latest={floor=7000},observations=1}
 local t2=M:PriceCheckReply(b);assert(t2:find('50s (TSM; our scan 2d old)',1,true),t2)
 -- Fresh ours wins.
 M.db.market[k].lastSeen=time()-600;M.db.latestScan=nil
 local t3=M:PriceCheckReply(b);assert(t3:find('70s (scanned 10m ago)',1,true),t3)
 -- Two whispers in the same second: the second waits a second.
 emit('CHAT_MSG_WHISPER','pc '..a,'Ann');emit('CHAT_MSG_WHISPER','pc '..b,'Bob')
 assert(#sent==1,'two replies in one second');advance(1);M:PriceCheckFlush();assert(#sent==2 and sent[2][3]=='Bob')
 -- Secret chat values (combat): ignored, no error.
 issecretvalue=function(v) return v=='SECRET' end
 advance(60);emit('CHAT_MSG_WHISPER','SECRET','Ann');assert(#sent==2)
 issecretvalue=nil;TSM_API=nil;SendChatMessage=nil;C_Timer=oldTimer
end)
check('1.23.34 price check reads quality-coloured links (|cnIQ) and /vmm pricecheck explains the last ask',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 local sent={};SendChatMessage=function(t,ch,_,to) sent[#sent+1]={t,ch,to} end
 local oldTimer=C_Timer;C_Timer=nil
 M.priceCheck.pending={};M.priceCheck.answered={};M.priceCheck.sent={};M.priceCheck.lastSend=nil;M.priceCheck.last=nil
 local link='|cnIQ1:|Hitem:5634::::::::60:::::::|h[Free Action Potion]|h|r'
 local key=M:LinkIdentity(link)
 M.db.market[key]={marketKey=key,itemID=5634,name='Free Action Potion',lastSeen=time()-60,latest={floor=25000},observations=1}
 emit('CHAT_MSG_WHISPER','price check '..link,'Redridge Chad')
 assert(#sent==1 and sent[1][1]=='VoidMark price: '..link..' 2g 50s (scanned 1m ago)' and sent[1][3]=='Redridge Chad',tostring(sent[1] and sent[1][1]))
 assert(M.priceCheck.last.reason=='sent to WHISPER Redridge Chad',M.priceCheck.last.reason)
 local printed={};local op=M.Print;M.Print=function(_,s) printed[#printed+1]=s end
 SlashCmdList.VOIDMARKMARKET('pricecheck '..link)
 M.Print=op
 local all=table.concat(printed,'\n')
 assert(all:find('whisper on',1,true) and all:find('sent to WHISPER',1,true) and all:find('Would reply: VoidMark price:',1,true),all)
 M.db.settings.priceCheckWhisper=false;advance(60)
 emit('CHAT_MSG_WHISPER','pc '..link,'Redridge Chad');assert(#sent==1)
 assert(M.priceCheck.last.reason:find('switched off',1,true))
 M.db.settings.priceCheckWhisper=nil;SendChatMessage=nil;C_Timer=oldTimer
end)
end
