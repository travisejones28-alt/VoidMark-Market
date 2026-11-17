return function(M,check)
check('1.23.39 mail subject fills from attachments, never overwrites typed text',function()
 local S=M.MailSubject; assert(S,'module loaded')
 local items={}; local money=0; local canSend=0
 GetSendMailItem=function(i) local it=items[i]; if it then return it,1,'tex',1 end end
 GetSendMailMoney=function() return money end
 SendMailFrame_CanSend=function() canSend=canSend+1 end
 local box={text='',GetText=function(self) return self.text end,SetText=function(self,t) self.text=t end}
 SendMailSubjectEditBox=box
 S.Fill(); assert(box.text=='','empty mail stays empty')
 items[1]='Linen Cloth'; S.Fill(); assert(box.text=='Linen Cloth',box.text); assert(canSend>0,'send button refreshed')
 items[2]='Linen Cloth'; items[3]='Wool Cloth'; items[5]='Silk Cloth'; S.Fill()
 assert(box.text=='Linen Cloth and 2 more',box.text)
 items={}; money=5000; S.Fill(); assert(box.text=='Gold',box.text)
 money=0; S.Fill(); assert(box.text=='','auto subject cleared when nothing attached')
 box.text='Herbs for the bank'; items[1]='Peacebloom'; S.Fill(); assert(box.text=='Herbs for the bank','typed subject kept')
 box.text=''; issecretvalue=function(v) return v=='SECRET' end; items={'SECRET'}; S.Fill(); assert(box.text=='','secret names skipped')
 issecretvalue=nil; SendMailSubjectEditBox=nil; S.Fill()
end)
end
