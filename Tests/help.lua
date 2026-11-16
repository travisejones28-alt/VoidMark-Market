-- Help window: every /vmm command the slash handler accepts is listed; it opens.
return function(M,check,addon)
local function read(p) local f=assert(io.open(p)); local s=f:read('*a'); f:close(); return s end
check('Help lists every /vmm command and opens from /vmm help and Settings',function()
 local core=read(addon..'Core.lua')
 local handler=core:sub((core:find('SlashCmdList.VOIDMARKMARKET=function',1,true)))
 handler=handler:sub(1,(handler:find('\nend\n',1,true)))
 local words={}
 for w in handler:gmatch("msg==%'([%w ]+)%'") do for x in w:gmatch('%w+') do words[x]=true end end
 for w in handler:gmatch("msg:match%(%'%^(%w+)") do words[w]=true end
 local listed={}
 for entry in read(addon..'Help.lua'):gmatch("{'(/vmm[^']*)'") do for x in entry:gmatch('%w+') do listed[x]=true end end
 local missing={}
 for w in pairs(words) do if not listed[w] and w~='faq' and w~='commands' then missing[#missing+1]=w end end
 table.sort(missing)
 assert(#missing==0,'Help.lua is missing /vmm '..table.concat(missing,', '))
 assert(next(words),'commands found')
 SlashCmdList.VOIDMARKMARKET('help snipe')
 local f=VoidMarkMarketHelp.Frame(); assert(f and f:IsShown(),'opens from /vmm help')
 local text,found=VoidMarkMarketHelp.Text('snipe'); assert(found>0 and text:find('/vmm snipe pct',1,true))
 f:Hide()
 if M.helpButton then M.helpButton.scripts.OnClick(M.helpButton); assert(f:IsShown(),'Settings button opens it') end
end)
end
