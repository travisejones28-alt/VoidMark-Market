-- 1.23.53: Your Items no longer blanks/flashes while the bag list rebuilds.
return function(M,check,jobs)
check('1.23.53 Your Items keeps the old list while rebuilding and does not restart mid-build',function()
 local old=C_Container
 C_Container={
  GetContainerNumSlots=function(bag) return bag==0 and 2 or 0 end,
  GetContainerItemInfo=function(bag,slot)
   if bag~=0 then return nil end
   return {itemID=4000+slot,hyperlink='|Hitem:'..(4000+slot)..':0:0:0:0:0:0:0|h[Thing]|h',stackCount=1}
  end
 }
 M.jobs={};M.bagsAgain=nil;M.bagsDirty=false
 M:RefreshInventory();jobs()
 assert(#M.sellingRows==2,'first build')
 local before=M.sellingRows
 M:RefreshInventory()
 assert(M.sellingRows==before and #M.sellingRows==2,'list blanked while rebuilding')
 local job=M.jobs.bags
 M:RefreshInventory()
 assert(M.jobs.bags==job and M.bagsAgain,'second refresh restarted the running build')
 jobs()
 assert(#M.sellingRows==2 and M.sellingRows~=before,'rebuild finished')
 assert(M.bagsDirty and not M.bagsAgain,'queued refresh runs once afterwards')
 M.bagsDirty=false
 C_Container=old
end)
check('1.23.53 an item whose name never loads rebuilds Your Items only once',function()
 local h=M.eventHandlers and M.eventHandlers.GET_ITEM_INFO_RECEIVED
 local oldView,oldWin,oldRows=M.view,M.window,M.sellingRows
 M.view='selling';M.window={IsShown=function() return true end}
 M.sellingRows={{itemID=777001,name='Item 777001'}};M.bagNameRetry=nil;M.bagsDirty=false
 local fire=function() if type(h)=='table' then for _,fn in ipairs(h) do fn(M,'GET_ITEM_INFO_RECEIVED',777001) end elseif h then h(M,'GET_ITEM_INFO_RECEIVED',777001) end end
 assert(h,'handler registered')
 fire();assert(M.bagsDirty,'first load rebuilds');M.bagsDirty=false
 fire();assert(not M.bagsDirty,'repeat events rebuild again')
 M.view,M.window,M.sellingRows=oldView,oldWin,oldRows
end)
end
