-- VoidMark Market help: FAQ and every command, opened from Settings or /vmm help.
-- Help window renderer. The same code ships in every VoidMark addon (one copy
-- per addon, own frame name), so each addon works on its own.
-- HELP = { title=..., intro=..., sections={ {title=..., commands={{'/cmd','what it does'},...}}
--                                            or {title=..., faq={{'Question?','Answer.'},...}} } }
local function HelpText(help,filter)
  filter=type(filter)=='string' and filter:lower():match('^%s*(.-)%s*$') or ''
  local function hit(...)
    if filter=='' then return true end
    for i=1,select('#',...) do
      local s=select(i,...)
      if type(s)=='string' and s:lower():find(filter,1,true) then return true end
    end
    return false
  end
  local out={}
  if filter=='' and help.intro then out[#out+1]=help.intro;out[#out+1]='' end
  local found=0
  for _,section in ipairs(help.sections or {}) do
    local lines={}
    for _,c in ipairs(section.commands or {}) do
      if hit(c[1],c[2],section.title) then lines[#lines+1]='|cffffd200'..c[1]..'|r  '..c[2];found=found+1 end
    end
    for _,q in ipairs(section.faq or {}) do
      if hit(q[1],q[2],section.title) then lines[#lines+1]='|cffffd200Q: '..q[1]..'|r';lines[#lines+1]='A: '..q[2];lines[#lines+1]='';found=found+1 end
    end
    if #lines>0 then
      out[#out+1]='|cffb86cff'..section.title:upper()..'|r'
      for _,l in ipairs(lines) do out[#out+1]=l end
      if lines[#lines]~='' then out[#out+1]='' end
    end
  end
  if found==0 then out[#out+1]='Nothing matches "'..filter..'".' end
  return table.concat(out,'\n'),found
end

local function HelpWindow(frameName,help)
  local w={help=help}
  local f,text,search
  local function render()
    if not f then return end
    local s=HelpText(help,search and search:GetText() or '')
    w.current=s
    text:SetText(s)
    local _,breaks=s:gsub('\n','\n')
    text:SetHeight(math.max(400,(breaks+1)*15+40))
  end
  local function build()
    f=CreateFrame('Frame',frameName,UIParent,BackdropTemplateMixin and 'BackdropTemplate' or nil)
    f:SetSize(580,620);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG')
    if f.SetToplevel then f:SetToplevel(true) end
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',function() f:StartMoving() end)
    f:SetScript('OnDragStop',function() f:StopMovingOrSizing() end)
    if f.SetBackdrop then
      f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
      f:SetBackdropColor(.035,.025,.06,.97);f:SetBackdropBorderColor(.48,.25,.72,1)
    end
    local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge')
    title:SetPoint('TOPLEFT',16,-14);title:SetText(help.title or 'Help')
    local close=CreateFrame('Button',nil,f,'UIPanelCloseButton')
    close:SetPoint('TOPRIGHT',-2,-2);close:SetScript('OnClick',function() f:Hide() end)
    local label=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    label:SetPoint('TOPLEFT',18,-48);label:SetText('Search:')
    search=CreateFrame('EditBox',frameName..'Search',f,'InputBoxTemplate')
    search:SetSize(220,20);search:SetPoint('TOPLEFT',70,-43)
    if search.SetAutoFocus then search:SetAutoFocus(false) end
    search:SetScript('OnTextChanged',function() render() end)
    search:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    search:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
    local hint=f:CreateFontString(nil,'OVERLAY','GameFontDisableSmall')
    hint:SetPoint('LEFT',search,'RIGHT',12,0);hint:SetText('Click the text, Ctrl+A, Ctrl+C to copy.')
    local scroll=CreateFrame('ScrollFrame',frameName..'Scroll',f,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',16,-72);scroll:SetPoint('BOTTOMRIGHT',-34,16)
    text=CreateFrame('EditBox',nil,scroll)
    if text.SetMultiLine then text:SetMultiLine(true) end
    if text.SetFontObject then text:SetFontObject(GameFontHighlight) end
    if text.SetAutoFocus then text:SetAutoFocus(false) end
    text:SetWidth(520)
    text:SetScript('OnEscapePressed',function(self) self:ClearFocus() end)
    -- Read only: typing puts the help text back.
    text:SetScript('OnTextChanged',function(self,user) if user and w.current then self:SetText(w.current) end end)
    scroll:SetScrollChild(text)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames+1]=frameName end
    f:Hide()
  end
  function w.Open(filter)
    if not f then build() end
    if filter~=nil and search then search:SetText(filter) end
    render();f:Show()
    return f
  end
  function w.Toggle()
    if f and f:IsShown() then f:Hide() else w.Open() end
  end
  function w.Text(filter) return HelpText(help,filter) end
  function w.Frame() return f end
  return w
end

local HELP={title='VoidMark Market: Help & commands',
 intro='Every command starts with /vmm (or /voidmarkmarket). Open this window from Settings > HELP & COMMANDS, or type /vmm help. Type in Search to filter. Market never buys, posts or cancels unless you click to confirm.',
 sections={
 {title='Window and scanning',commands={
  {'/vmm','Open or close the Market window.'},
  {'/vmm help [word]','This window; a word searches it.'},
  {'/vmm scan','Full Auction House scan (at the AH).'},
  {'/vmm cached','Read the AH data the game already has without a new scan.'},
  {'/vmm scanspeed fast | normal | smooth','How hard scans work each frame (smooth = fewer hitches).'},
  {'/vmm gold','Gold-making view.'},
  {'/vmm version','Version and who you are paired with.'}}},
 {title='Prices and deals',commands={
  {'/vmm check [item]','Hover an item (or Shift-click one after typing) to check its price.'},
  {'/vmm tipcheck','Price details for the item under your mouse (good on a key or macro).'},
  {'/vmm deal 50','Deals show green at this % of the 30-day average or less (10-100).'},
  {'/vmm snipe','Turn the misposting sniper on/off and show hits.'},
  {'/vmm snipe on | off | hits | sound','Start, stop, show hits, sniper sound on/off.'},
  {'/vmm snipe pct 40','Flag items at this % of their average or less (5-90).'},
  {'/vmm snipe min 1g','Only flag items you would gain at least this much on.'},
  {'/vmm pricecheck [item]  (or /vmm pc)','Price-check reply status; with an item, what you would reply.'}}},
 {title='Flipping',commands={
  {'/vmm flips  (or /vmm ledger)','Flip Ledger: what you paid, when, and what it sold for.'},
  {'/vmm flipmax 15','Search terms only show items at this many silver or less (0 = off).'},
  {'/vmm flipstarter','Add starter search terms to your Shopping list.'},
  {'/vmm flipsync','Send all your buys to your synced partner again.'},
  {'/vmm flipsrebuild','Rebuild the Flip Ledger from your history (no doubles).'},
  {'/vmm paidfloor on | off','Never suggest selling below what you paid + AH cut.'},
  {'/vmm salealerts on | off','Purple banner and chat line when an auction sells.'},
  {'/vmm salesound on | off','Sale chime on or off.'},
  {'/vmm testsound','Play the sale sound.'},
  {'/vmm void','Hidden shopping lists menu.'},
  {'/vmm void NAME [off]','Unlock (or hide again) a hidden list by its name.'}}},
 {title='Crafting and disenchanting',commands={
  {'/vmm craft','Crafting profits.'},
  {'/vmm craftscan','Read the open profession window.'},
  {'/vmm materials','Materials shopping list for crafting.'},
  {'/vmm de  (or /vmm disenchant)','What to disenchant from your bags.'},
  {'/vmm de ah','Disenchant deals on the Auction House.'},
  {'/vmm de tooltip','Disenchant values in tooltips on or off.'}}},
 {title='Bank sync',commands={
  {'/vmm realm','Which realm Market is using, and what the game reported.'},
  {'/vmm peer','Pairing status.'},
  {'/vmm peer Name-Realm','Pair with your other account\'s character (do it on both).'},
  {'/vmm peer off','Unpair.'}}},
 {title='Problems',commands={
  {'/vmm report','Build, scan, sync and transaction diagnostics.'},
  {'/vmm diag','Diagnostics view.'},
  {'/vmm probe','Test which Auction House functions this client offers.'},
  {'/vmm perf','Measure performance for 10 seconds.'},
  {'/vmm debug','Extra debug messages on or off.'}}},
 {title='Every VoidMark addon',commands={
  {'Whisper "inv" or "invite"','From one of your Voidmark characters: you get a group invite.'}}},
 {title='FAQ',faq={
  {'Will Market buy or post on its own?','No. It never trades at login, from timers, scans, lists or messages. Every buy, post and cancel needs your click and confirmation.'},
  {'How do I share prices with my main?','Settings > Partner: type the other character\'s name and click PAIR on both accounts. Keep both online; the bank\'s scans reach the main by themselves.'},
  {'What do CURRENT and STALE mean on tooltips?','CURRENT is from a recent scan. STALE is older than your maximum model age: check the AH before trusting it.'},
  {'How do I move or resize the Auction House?','Left-drag an empty part to move it; right-drag the title bar to resize. Settings > RESET WINDOW puts it back.'},
  {'What is the sniper?','It watches scans for items posted far below their average (misposts) and lists them as hits. Set the % and minimum gain with /vmm snipe pct and /vmm snipe min.'},
  {'How do I copy prices without both online?','Transfer > Export Prices on one client, paste and Import Pasted Text on the other.'},
  {'A price looks wrong.','Hover it to see the source and age. Run a fresh /vmm scan at the AH. /vmm report helps find sync or scan problems.'},
  {'Can I use Auctionator at the same time?','Yes. Market\'s tabs are then labelled VM Shopping, VM Selling and so on.'}}}}}
_G.VoidMarkMarketHelp=HelpWindow('VoidMarkMarketHelpWindow',HELP)
