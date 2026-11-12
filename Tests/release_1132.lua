return function(M,check,jobs,advance,emit)
check('1.13.2 Listings tab name; your auctions load first; bank sync runs last',function()
 -- Tab label (internal key unchanged for saved settings).
 local tab;for _,s in ipairs(M.auctionSections) do if s.root=='my auctions' then tab=s end end
 assert(tab.label=='Listings' and tab.key=='cancelling','tab label')
 -- Owned auctions jump ahead of name/list searches in the AH queue.
 local q=M.queue;local saved=q.waiting;q.waiting={}
 local oldPump=M.PumpQueue;M.PumpQueue=function() end
 M:QueueRequest({id='list-a',kind='search',priority=20});M:QueueRequest({id='browse-name',kind='browse',priority=50})
 M:RequestOwnedAuctionsDiagnostic()
 assert(q.waiting[1].id=='owned','owned should be first, got '..tostring(q.waiting[1].id))
 q.waiting=saved;q.dedupe={};M.PumpQueue=oldPump
 -- Job order: things you wait on, then background work, then bank sync with leftover time only.
 local oldJobs,oldClock=M.jobs,debugprofilestop
 local t=0;debugprofilestop=function() return t end
 local ran={}
 M.jobs={}
 M:AddJob('share-scan',function() ran[#ran+1]='sync' end)
 M:AddJob('scan',function() ran[#ran+1]='scan';t=t+100 end)        -- uses the whole frame
 M:AddJob('owned',function() ran[#ran+1]='owned' end)
 M:RunJobs()
 assert(table.concat(ran,',')=='owned,scan','sync must wait when the frame is used up: '..table.concat(ran,','))
 ran={};M.jobs.scan=nil;M:RunJobs()
 assert(ran[#ran]=='sync','sync runs once there is time: '..table.concat(ran,','))
 M.jobs,debugprofilestop=oldJobs,oldClock
end)
end
