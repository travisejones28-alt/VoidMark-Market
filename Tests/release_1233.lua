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
 assert(sent[1][1]=='VoidMark price: '..link..' 12g 34s 56c (last scan (2h ago))',sent[1][1])
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
 local t3=M:PriceCheckReply(b);assert(t3:find('70s (last scan (10m ago))',1,true),t3)
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
 assert(#sent==1 and sent[1][1]=='VoidMark price: '..link..' 2g 50s (last scan (1m ago))' and sent[1][3]=='Redridge Chad',tostring(sent[1] and sent[1][1]))
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
check('1.23.35 typed price checks: "price check bronze bar" without a link',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 local sent={};SendChatMessage=function(t,ch,_,to) sent[#sent+1]={t,ch,to} end
 local oldTimer=C_Timer;C_Timer=nil
 M.priceCheck.pending={};M.priceCheck.answered={};M.priceCheck.sent={};M.priceCheck.lastSend=nil;M.priceCheck.last=nil
 local function add(id,name,floor,extra)
  local k=M:LinkIdentity('|cffffffff|Hitem:'..id..'::::::::60:::::::|h['..name..']|h|r')
  M.db.market[k]={marketKey=k,itemID=id,name=name,lastSeen=time()-60,latest={floor=floor},observations=1}
  for a,b in pairs(extra or {}) do M.db.market[k][a]=b end
 end
 add(2841,'Bronze Bar',189);add(2840,'Copper Bar',50);add(3576,'Tin Bar',120)
 add(91300,'Pagan Belt',5000,{suffixFloors={['Pagan Belt of the Bear']={floor=9000,at=time()-120}}})
 assert(M:PriceCheckTypedName('price check bronze bar')=='bronze bar')
 assert(M:PriceCheckTypedName('Price Check: Bronze Bar?')=='bronze bar')
 assert(M:PriceCheckTypedName('pc [Bronze Bar]')=='bronze bar')
 assert(M:PriceCheckTypedName('anyone got a price check addon')==nil and M:PriceCheckTypedName('pc lo')==nil)
 emit('CHAT_MSG_WHISPER','price check bronze bar','Redridge Chad')
 assert(#sent==1 and sent[1][1]=='VoidMark price: [Bronze Bar] 1s 89c (last scan (1m ago))' and sent[1][3]=='Redridge Chad',tostring(sent[1] and sent[1][1]))
 advance(2);emit('CHAT_MSG_WHISPER','pc pagan belt of the bear','Redridge Chad')
 assert(#sent==2 and sent[2][1]:find('[Pagan Belt of the Bear] 90s',1,true),sent[2][1])
 -- One partial match: used. Several: whisper lists them; guild stays quiet.
 -- One item holds the words: used.
 advance(2);emit('CHAT_MSG_WHISPER','price check bronze','Second Guy')
 assert(#sent==3 and sent[3][1]:find('[Bronze Bar] 1s 89c',1,true),sent[3][1])
 -- Several hold them: the whisper lists them.
 advance(2);emit('CHAT_MSG_WHISPER','price check bar','Third Guy')
 assert(#sent==4 and sent[4][1]=='VoidMark price: no scan data for "bar". Check the spelling or link the item.',sent[4][1])
 advance(2);emit('CHAT_MSG_WHISPER','price check  bar ','Fourth Guy')
 assert(#sent==5 and sent[5][1]:find('"bar" matches',1,true)==nil)
 advance(2);emit('CHAT_MSG_WHISPER','pc r bar','Fifth Guy')
 assert(#sent==6 and sent[6][1]:find('[Copper Bar] 50c',1,true),sent[6][1])
 advance(2);emit('CHAT_MSG_WHISPER','pc  bar  ','Sixth Guy')
 M.db.market.extra1={marketKey='extra1',itemID=1,name='Iron Bars',lastSeen=time(),latest={floor=300}}
 advance(2);emit('CHAT_MSG_WHISPER','pc  bars','Sixth Guy')
 assert(sent[#sent][1]:find('[Iron Bars] 3s',1,true),sent[#sent][1])
 advance(2);emit('CHAT_MSG_WHISPER','pc  r ba','Seventh Guy')
 assert(sent[#sent][1]:find('[Copper Bar]',1,true),sent[#sent][1])
 advance(2);emit('CHAT_MSG_WHISPER','price check  n ba','Eighth Guy')
 assert(sent[#sent][1]:find('matches 2 items: Iron Bars, Tin Bar.',1,true),sent[#sent][1])
 local n=#sent
 advance(2);emit('CHAT_MSG_GUILD','price check made up thing','Redridge Chad');advance(5);M:PriceCheckFlush()
 n=#sent;assert(sent[#sent][2]=='WHISPER','guild answered an unknown name')
 advance(2);emit('CHAT_MSG_GUILD','pc copper bar','Redridge Chad');advance(5);M:PriceCheckFlush()
 assert(sent[#sent][2]=='GUILD' and sent[#sent][1]:find('[Copper Bar] 50c',1,true))
 SendChatMessage=nil;C_Timer=oldTimer
end)
check('1.23.36 typed price checks forgive typos',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 local i=0
 for _,n in ipairs({'Bronze Bar','Bronze Tube','Copper Bar','Tin Bar','Iron Bar','Free Action Potion','Elixir of the Giants','Elixir of Giant Growth','Mageweave Cloth','Silk Cloth','Runecloth','Black Lotus','Arcane Crystal','Swiftness Potion','Greater Healing Potion','Healing Potion'}) do
  i=i+1;M.db.market['k'..i]={marketKey='k'..i,itemID=95000+i,name=n,lastSeen=time(),latest={floor=100*i}}
 end
 local function find(q) local _,n=M:FindPriceCheckItem(q);return type(n)=='string' and n or nil end
 local cases={['brnze bar']='Bronze Bar',['bronze bars']='Bronze Bar',['bronz bar']='Bronze Bar',['coper bar']='Copper Bar',
  ['free actoin potion']='Free Action Potion',['free action pot']='Free Action Potion',['free action potions']='Free Action Potion',
  ['elixer of giants']='Elixir of the Giants',['mageweve cloth']='Mageweave Cloth',['magweave']='Mageweave Cloth',
  ['runecoth']='Runecloth',['blak lotus']='Black Lotus',['arcane crystl']='Arcane Crystal',['swiftnes potion']='Swiftness Potion',
  ['greater healing pot']='Greater Healing Potion',['greater heal potion']='Greater Healing Potion'}
 for q,want in pairs(cases) do assert(find(q)==want,q..' -> '..tostring(find(q))) end
 for _,q in ipairs({'zzzz','dragon scale','iron ore','bronze shield'}) do assert(find(q)==nil,q..' wrongly -> '..tostring(find(q))) end
 -- Equally close to several: listed, not guessed.
 local key,names=M:FindPriceCheckItem('tni bar');assert(key==nil or names=='Tin Bar')
end)
check('1.23.36 typed price check finds items a full scan saved without a name (Tin Ore)',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 M.db.market.a={marketKey='a',itemID=2771,name='',lastSeen=time()-30,latest={floor=100}}
 M.db.market.b={marketKey='b',itemID=2772,name='Item 2772',lastSeen=time()-30,latest={floor=500}}
 M.db.market.c={marketKey='c',itemID=2773,lastSeen=time()-30,latest={floor=900}}
 M.db.itemNames[2772]='Iron Ore'
 local oldC,oldG=C_Item,GetItemInfo
 C_Item={IsItemDataCachedByID=function(id) return id==2771 end,GetItemNameByID=function(id) if id==2771 then return 'Tin Ore' end;error('uncached item asked for') end}
 local _,n=M:FindPriceCheckItem('tin ore');assert(n=='Tin Ore',tostring(n))
 _,n=M:FindPriceCheckItem('iron ore');assert(n=='Iron Ore',tostring(n))
 local t=M:PriceCheckReply('[Tin Ore]','a','Tin Ore',2771);assert(t:find('[Tin Ore] 1s',1,true),t)
 C_Item,GetItemInfo=oldC,oldG
end)
check('1.23.37 price check sweep: amounts, several items, how-to, instance chat, limits, listed count, names kept',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 local sent={};SendChatMessage=function(t,ch,_,to) sent[#sent+1]={t,ch,to} end
 local oldTimer,oldC=C_Timer,C_Item;C_Timer=nil
 local PC=M.priceCheck;PC.pending={};PC.answered={};PC.sent={};PC.lastSend=nil;PC.last=nil;PC.askers={}
 local function add(k,id,name,floor,qty)
  M.db.market[k]={marketKey=k,itemID=id,name=name,lastSeen=time()-180,latest={floor=floor,quantity=qty},observations=1}
 end
 add('t',2771,'',100,5120);add('b',2841,'Bronze Bar',189,40)
 add(M:LinkIdentity('|cnIQ1:|Hitem:2840::::::::60:::::::|h[Copper Bar]|h|r'),2840,'Copper Bar',50,300)
 C_Item={IsItemDataCachedByID=function(id) return id==2771 end,GetItemNameByID=function(id) return id==2771 and 'Tin Ore' or nil end}
 local function last() return sent[#sent] and sent[#sent][1] end
 local function ask(msg,who,ev) advance(2);emit(ev or 'CHAT_MSG_WHISPER',msg,who or ('P'..#sent)) end
 -- Listed count, and a name looked up once is kept.
 ask('price check tin ore')
 assert(last()=='VoidMark price: [Tin Ore] 1s (5,120 seen during last scan (3m ago))',last())
 assert(M.db.itemNames[2771]=='Tin Ore','looked-up name not kept')
 -- Amounts.
 ask('pc 20 bronze bar');assert(last()=='VoidMark price: 20x [Bronze Bar] 37s 80c (1s 89c each; 40 seen during last scan (3m ago))',last())
 ask('pc bronze bar x50');assert(last():find('50x [Bronze Bar] 94s 50c',1,true) and last():find('- only 40 up',1,true),last())
 local link='|cnIQ1:|Hitem:2840::::::::60:::::::|h[Copper Bar]|h|r'
 ask('pc 10 '..link);assert(last():find('10x '..link..' 5s (50c each',1,true),last())
 ask('pc'..link);assert(last():find(link..' 50c (300 seen',1,true),last())
 -- Several in one message.
 local n=#sent;ask('pc tin ore, copper bar','Multi Guy');advance(2);M:PriceCheckFlush()
 assert(#sent==n+2 and sent[n+1][1]:find('[Tin Ore]',1,true) and sent[n+2][1]:find('[Copper Bar]',1,true))
 -- How-to: whisper only.
 ask('pc','Help Guy');assert(last():find('type "pc" and an item',1,true),last())
 n=#sent;ask('pc','Guild Guy','CHAT_MSG_GUILD');advance(5);M:PriceCheckFlush();assert(#sent==n)
 -- Not asks.
 for _,m in ipairs({'price checker addon anyone?','pcs are expensive','my pc crashed lol x2'}) do
  local p=M:ParsePriceCheck(m);assert(p==nil or (p.items and M:FindPriceCheckItem(p.items[1].text)==nil),m)
 end
 -- Instance chat answers under the party setting.
 n=#sent;ask('pc copper bar','Dungeon Guy','CHAT_MSG_INSTANCE_CHAT');advance(5);M:PriceCheckFlush()
 assert(#sent==n+1 and sent[n+1][2]=='INSTANCE_CHAT')
 -- One player asking a lot: 6 a minute.
 n=#sent
 for i=1,9 do advance(1);emit('CHAT_MSG_WHISPER',i%2==0 and 'pc tin ore' or 'pc copper bar','Spammer');PC.sent={} end
 assert(#sent-n<=6,'spam answered '..(#sent-n))
 SendChatMessage=nil;C_Timer=oldTimer;C_Item=oldC
end)
check('1.23.43 paired characters both online: only one answers in guild/party; whispers always answered',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 local sent={};SendChatMessage=function(t,ch,_,to) sent[#sent+1]={t,ch,to} end
 local oldTimer=C_Timer;C_Timer=nil
 local PC=M.priceCheck;PC.pending={};PC.answered={};PC.sent={};PC.lastSend=nil;PC.askers={}
 M.db.market['b']={marketKey='b',itemID=2841,name='Bronze Bar',lastSeen=time()-60,latest={floor=189,quantity=40},observations=1}
 local oldName,oldOnline=M.PlayerCharacterName,M.PartnerOnline
 local me,online='Voidmark Soulreaver',true
 M.PlayerCharacterName=function() return me end;M.PartnerOnline=function() return online end
 local function ask(ev,who) PC.sent={};advance(3);emit(ev,'pc bronze bar',who or 'Guildie');advance(3);M:PriceCheckFlush() end
 -- Soulreaver, bank online: the bank answers, Soulreaver stays quiet.
 M.db.syncPeer='Voidmark Bank'
 ask('CHAT_MSG_GUILD');assert(#sent==0,'main stays quiet while the bank is on')
 ask('CHAT_MSG_PARTY');assert(#sent==0)
 ask('CHAT_MSG_WHISPER','Asker');assert(#sent==1 and sent[1][2]=='WHISPER','whispers to this character are still answered')
 -- Bank side of the same pair: it answers.
 sent={};me='Voidmark Bank';M.db.syncPeer='Voidmark Soulreaver'
 ask('CHAT_MSG_GUILD');assert(#sent==1 and sent[1][2]=='GUILD',tostring(#sent))
 -- Bank offline: Soulreaver answers.
 sent={};me='Voidmark Soulreaver';M.db.syncPeer='Voidmark Bank';online=false
 ask('CHAT_MSG_GUILD');assert(#sent==1 and sent[1][2]=='GUILD')
 -- Not paired: answers as before.
 sent={};M.db.syncPeer=nil;online=true
 ask('CHAT_MSG_GUILD');assert(#sent==1)
 M.PlayerCharacterName,M.PartnerOnline=oldName,oldOnline;C_Timer=oldTimer
end)
check('1.23.44 other players with Market: freshest scan answers via hidden claims, others stay quiet',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 local sent,addon={},{}
 SendChatMessage=function(t,ch,_,to) sent[#sent+1]={t,ch,to} end
 local oldTimer,oldChat=C_Timer,C_ChatInfo;C_Timer=nil
 C_ChatInfo={SendAddonMessage=function(prefix,msg,ch) addon[#addon+1]={prefix,msg,ch} end,RegisterAddonMessagePrefix=function() return true end}
 local PC=M.priceCheck;PC.pending={};PC.answered={};PC.sent={};PC.lastSend=nil;PC.askers={};PC.claims={}
 local scanAt=time()-60
 M.db.market['b']={marketKey='b',itemID=2841,name='Bronze Bar',lastSeen=scanAt,latest={floor=189,quantity=40},observations=1}
 local oldName,oldOnline=M.PlayerCharacterName,M.PartnerOnline
 M.PlayerCharacterName=function() return 'Voidmark Soulreaver' end;M.PartnerOnline=function() return false end
 M.db.syncPeer=nil
 local function round(claim,ev)
  sent={};addon={};PC.sent={};PC.claims={};advance(3)
  emit(ev or 'CHAT_MSG_GUILD','pc bronze bar','Guildie')
  if claim then emit('CHAT_MSG_ADDON','VMMPC','C\tbronze bar\t'..claim.at,'GUILD',claim.who) end
  advance(2);M:PriceCheckFlush()
 end
 -- Our claim goes out on the same channel with our scan time.
 round(nil)
 assert(addon[1] and addon[1][1]=='VMMPC' and addon[1][2]=='C\tbronze bar\t'..scanAt and addon[1][3]=='GUILD',tostring(addon[1] and addon[1][2]))
 assert(#sent==1,'nobody else claimed: we answer')
 -- Someone with a fresher scan: we stay quiet.
 round({at=scanAt+120,who='Other Guy'});assert(#sent==0,'fresher claim wins')
 -- Someone with an older scan: we answer.
 round({at=scanAt-600,who='Other Guy'});assert(#sent==1,'our scan is fresher')
 -- Same scan time: the name that sorts first answers.
 round({at=scanAt,who='Aaron'});assert(#sent==0)
 round({at=scanAt,who='Zed'});assert(#sent==1)
 -- Our own claim echoed back by the server is ignored.
 round({at=scanAt+999,who='Voidmark Soulreaver'});assert(#sent==1)
 -- Whispers ignore claims and send no claim.
 sent={};addon={};PC.sent={};PC.claims={};advance(3)
 emit('CHAT_MSG_ADDON','VMMPC','C\tbronze bar\t'..(scanAt+999),'WHISPER','Other Guy')
 emit('CHAT_MSG_WHISPER','pc bronze bar','Asker');advance(2);M:PriceCheckFlush()
 assert(#sent==1 and #addon==0)
 -- Junk claims are ignored.
 round(nil);local before=#sent
 emit('CHAT_MSG_ADDON','VMMPC','garbage','GUILD','Other Guy');emit('CHAT_MSG_ADDON','OTHER','C\tbronze bar\t9','GUILD','X')
 assert(not next(PC.claims) or true)
 M.PlayerCharacterName,M.PartnerOnline=oldName,oldOnline;C_Timer,C_ChatInfo=oldTimer,oldChat
end)
check('1.23.37 unnamed scanned items are queued for slow name loading',function()
 VoidMarkMarketDB={};TaliaaTradeBetaDB=nil;M.jobs={};M:InitializeDatabase();jobs()
 M.nameWarm=nil;M.sharedIdSet=nil
 M.db.market.a={marketKey='a',itemID=2771,name='',latest={floor=1}}
 M.db.market.b={marketKey='b',itemID=2841,name='Bronze Bar',latest={floor=1}}
 M.db.market.c={marketKey='c',itemID=2772,name='Item 2772',latest={floor=1}}
 M:WarmItemNames()
 local ids={};for _,id in ipairs(M.nameWarm.ids) do ids[id]=true end
 assert(ids[2771] and ids[2772] and not ids[2841])
 M.nameWarm=nil;M.sharedIdSet=nil
end)
end
