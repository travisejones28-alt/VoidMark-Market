-- 1.23.52: a recipe's tooltip is priced as the recipe, not the crafted item it embeds.
return function(M,check)
check('1.23.52 recipe tooltip prices the recipe, not the crafted item inside it',function()
 local oldTDP,oldEnum,oldInfo=TooltipDataProcessor,Enum,GetItemInfo
 local post
 TooltipDataProcessor={AddTooltipPostCall=function(_,fn) post=fn end}
 Enum=setmetatable({TooltipDataType={Item=0}},{__index=oldEnum})
 GetItemInfo=function(id)
  if id==14499 then return 'Pattern: Mooncloth Bag','|cff1eff00|Hitem:14499::::::::60:::::|h[Pattern: Mooncloth Bag]|h|r' end
  return oldInfo(id)
 end
 M.tooltipHooked=nil
 M:InitializePriceTooltips()
 assert(post,'post-call registered')
 local now=time()
 M.db.market[14499]={name='Pattern: Mooncloth Bag',lastSeen=now-60,latest={floor=48000,at=now-60,quantity=7}}
 M.db.market[14155]={name='Mooncloth Bag',lastSeen=now-60,latest={floor=890000,at=now-60,quantity=13}}
 local lines={}
 local tip={GetItem=function() return 'Mooncloth Bag','|cff1eff00|Hitem:14155::::::::60:::::|h[Mooncloth Bag]|h|r' end,
  AddDoubleLine=function(_,l,r) lines[#lines+1]=tostring(l)..'='..tostring(r) end,AddLine=function() end,GetName=function() return nil end}
 post(tip,{id=14499})
 local text=table.concat(lines,' | ')
 assert(text:find(M:Coins(48000),1,true),'recipe price missing: '..text)
 assert(not text:find(M:Coins(890000),1,true),'crafted item price shown: '..text)
 assert(text:find('7 seen',1,true),'recipe count missing: '..text)
 -- normal item: data matches GetItem, unchanged
 lines={}
 tip.GetItem=function() return 'Mooncloth Bag','|cff1eff00|Hitem:14155::::::::60:::::|h[Mooncloth Bag]|h|r' end
 post(tip,{id=14155})
 assert(table.concat(lines,' | '):find(M:Coins(890000),1,true),'normal item price')
 TooltipDataProcessor,Enum,GetItemInfo=oldTDP,oldEnum,oldInfo
end)
end
