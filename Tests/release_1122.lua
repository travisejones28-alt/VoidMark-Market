return function(M,check,jobs,advance,emit)
-- 1.12.2 Tooltip stack totals never borrow another slot's stack size.
local function owner(name,id,parentID)
 local parent={GetID=function() return parentID end}
 return {GetName=function() return name end,GetID=function() return id end,GetParent=function() return parent end}
end
local function tipFor(o) return {GetOwner=function() return o end} end
check('1.12.2 Mail attachments show their own stack size, not a bag slot with the same number',function()
 local oldC,oldSend,oldInbox,oldFrame=C_Container,GetSendMailItem,GetInboxItem,InboxFrame
 local rosecap='|Hitem:8836:0:0:0:0:0:0:0|h[Rosecap]|h'
 -- Backpack slot 5 holds 20 Heavy Leather; mail attachment 5 holds 2 Rosecap (the bug report).
 C_Container={GetContainerItemInfo=function(bag,slot)
  if bag==0 and slot==5 then return {itemID=4234,hyperlink='|Hitem:4234:0|h[Heavy Leather]|h',stackCount=20} end
  if bag==0 and slot==7 then return {itemID=8836,hyperlink=rosecap,stackCount=2} end end}
 GetSendMailItem=function(i) if i==5 then return 'Rosecap',8836,134215,2,1,true end end
 local ok,err=pcall(function()
  assert(M:TooltipStackCount(tipFor(owner('SendMailAttachment5',5,0)),rosecap)==2,'send mail attachment count')
  GetSendMailItem=function(i) if i==5 then return 'Rosecap',134215,2,1,true end end -- older return shape
  assert(M:TooltipStackCount(tipFor(owner('SendMailAttachment5',5,0)),rosecap)==2,'older send mail shape')
  InboxFrame={openMailID=3}
  GetInboxItem=function(m,i) if m==3 and i==2 then return 'Rosecap',8836,134215,4,1,true end end
  assert(M:TooltipStackCount(tipFor(owner('OpenMailAttachmentButton2',2,0)),rosecap)==4,'inbox attachment count')
  -- Any other button whose ID points at a bag slot holding a different item: no stack line.
  assert(M:TooltipStackCount(tipFor(owner('MerchantItem5ItemButton',5,0)),rosecap)==nil,'borrowed another item stack')
  -- Real bag slot with the same item still works.
  assert(M:TooltipStackCount(tipFor(owner('ContainerFrame1Item3',7,0)),rosecap)==2,'bag slot stack lost')
 end)
 C_Container,GetSendMailItem,GetInboxItem,InboxFrame=oldC,oldSend,oldInbox,oldFrame
 assert(ok,err)
end)
end
