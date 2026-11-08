local _,M=...
-- Auctionator-style Cancelling screen (own implementation, VoidMark styling).
local function label(parent,text,x,y,w,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontNormalSmall');f:SetPoint('TOPLEFT',x,y)
 if w then f:SetWidth(w) end;f:SetJustifyH('LEFT');f:SetText(text or '');return f
end
local function button(parent,text,x,y,w,fn,h)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,h or 24);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local ROWS=16
local COLS={{'Item',40,330},{'Qty',376,60},{'Your price / unit',442,160},{'Lowest other',608,150},{'Time left',764,100},{'State',870,120}}

-- Undercut listings first, then not-checked, then the rest; stable by name.
function M:CancelRows()
 local rank=function(o)
  if self:OwnedSold(o) then return 4 elseif o.undercut then return 1 elseif not o.liveAt then return 2 end
  return 3
 end
 local out={}
 for i,o in ipairs(self.ownedRows or {}) do out[i]=o end
 table.sort(out,function(a,b)
  local ra,rb=rank(a),rank(b);if ra~=rb then return ra<rb end
  local na,nb=tostring(a.name or ''),tostring(b.name or '');if na~=nb then return na<nb end
  return (a.auctionID or 0)<(b.auctionID or 0)
 end)
 return out
end

function M:InitializeCancelScreen(f)
 local s=CreateFrame('Frame',nil,f);s:SetPoint('TOPLEFT',18,-108);s:SetSize(1004,554);s:Hide();self.cancelScreen=s
 local list=self.panel(s,0,0,1004,474);s.list=list
 s.title=label(list,'Your auctions',14,-10,500,'GameFontNormal')
 for _,c in ipairs(COLS) do label(list,c[1],c[2],-32,c[3]) end
 s.rows={}
 for i=1,ROWS do
  local r=CreateFrame('Button',nil,list);r:SetPoint('TOPLEFT',6,-50-(i-1)*26);r:SetSize(990,25)
  r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  r.sel=r:CreateTexture(nil,'BACKGROUND');r.sel:SetAllPoints();r.sel:SetColorTexture(.32,.15,.5,.45)
  r.icon=r:CreateTexture(nil,'ARTWORK');r.icon:SetSize(20,20);r.icon:SetPoint('LEFT',8,0)
  r.c={}
  for j,c in ipairs(COLS) do r.c[j]=label(r,'',c[2]-6,-7,c[3],'GameFontHighlight') end
  r:SetScript('OnClick',function(b) if b.data then self.selectedRow=b.data;self:AnalyzeOwnedLive(b.data) end end)
  r:SetScript('OnEnter',function(b) self:ShowRowTooltip(b) end)
  r:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  s.rows[i]=r
 end
 list:EnableMouseWheel(true)
 list:SetScript('OnMouseWheel',function(_,d) self.cancelPage=math.max(1,(self.cancelPage or 1)-(d>0 and 1 or -1));self:RefreshUI() end)
 s.empty=label(list,'',14,-220,976,'GameFontHighlight');s.empty:SetJustifyH('CENTER')
 s.summary=label(s,'',0,-482,1004,'GameFontHighlight')
 s.refresh=button(s,'Refresh',0,-510,150,function() self:RequestOwnedAuctionsDiagnostic() end,30)
 s.check=button(s,'Check undercuts',158,-510,190,function() self:CheckAllUndercuts() end,30)
 s.cancel=button(s,'Cancel selected...',356,-510,190,function() self:ReviewCancel(self.selectedRow) end,30)
 s.next=button(s,'Cancel next undercut...',554,-510,230,function() self:CancelNextUndercut() end,30)
 s.page=label(s,'',790,-518,214,'GameFontHighlightSmall');s.page:SetJustifyH('RIGHT')
end

function M:RenderCancelScreen()
 local s=self.cancelScreen;if not s then return end
 s:Show()
 local rows=self:CancelRows();local pages=math.max(1,math.ceil(#rows/ROWS))
 self.cancelPage=math.min(self.cancelPage or 1,pages)
 for i,r in ipairs(s.rows) do
  local o=rows[(self.cancelPage-1)*ROWS+i];r.data=o;r:SetShown(o~=nil)
  if o then
   r.sel:SetShown(self.selectedRow==o)
   r.icon:SetTexture(self:RowItemIcon(o,o.itemKey and o.itemKey.itemID or o.itemID) or 'Interface\\Icons\\INV_Misc_QuestionMark')
   local cells={tostring(o.name or '?'),tostring(o.quantity or '?'),o.unit and self:Coins(o.unit) or '?',
    o.competition and self:Coins(o.competition) or (o.liveAt and 'None' or '--'),self:FormatTimeLeft(o.timeLeft),self:OwnedState(o)}
   for j=1,#cells do r.c[j]:SetText(cells[j]) end
  end
 end
 local u,l,n=self:UndercutSummary()
 local sel=self.selectedRow
 local selText=sel and sel.reason and (' | '..tostring(sel.name)..': '..sel.reason) or ''
 s.summary:SetText(#rows>0 and ('|cffff6655'..u..' undercut|r   |cff72e7aa'..l..' lowest|r   '..n..' not checked'..selText) or '')
 local empty=''
 if #rows==0 then empty=self.ahOpen and 'You have no auctions up. Click Refresh if you just posted.' or 'Open the Auction House to see your auctions.' end
 s.empty:SetText(empty);s.empty:SetShown(empty~='')
 s.title:SetText('Your auctions ('..#rows..')')
 s.page:SetText(pages>1 and ('page '..self.cancelPage..' / '..pages..'  (scroll)') or '')
 local live=self.ahOpen and true or false
 s.refresh:SetEnabled(live);s.check:SetEnabled(live and #rows>0)
 s.cancel:SetEnabled(live and sel~=nil and not self:OwnedSold(sel))
 s.next:SetEnabled(live and u>0)
end
