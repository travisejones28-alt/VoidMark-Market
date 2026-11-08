local _,M=...
-- Green flips: uncommon gear with sought-after stat suffixes listed far below
-- what it resells for. Buy cheap, relist just under the next posted price.
-- Uses the latest full scan only; buying goes through the normal Buy screen.
M.defaults.flipMaxBuy=1500        -- 15s
M.defaults.flipMinProfit=1000     -- 10s after AH cut and deposit
M.defaults.flipDefaultSell=3500   -- 35s when nobody else lists the same item
M.defaults.flipWords='Healing,Magic,Agility,Monkey,Intellect,Tiger'

function M:FlipWords()
 local out={}
 for w in tostring(self.db.settings.flipWords or ''):gmatch('[^,]+') do
  w=w:match('^%s*(.-)%s*$'); if w~='' then out[#out+1]=w:lower() end
 end
 return out
end
-- Display name with the suffix, taken from the item link label when present.
function M:FlipName(m)
 local label=type(m.itemLink)=='string' and m.itemLink:match('|h%[(.-)%]|h')
 return label or m.name or ('Item '..tostring(m.itemID))
end
-- Rough deposit: 15% of vendor value (estimate only; the real one shows when posting).
function M:FlipDeposit(m) return math.ceil((tonumber(m.vendorPrice) or 0)*0.15) end

-- Returns a flip row for one market, or nil.
function M:FlipCandidate(m,words,newest)
 local l=m and m.latest; if type(l)~='table' or m.archived or m.analysisIncomplete then return nil end
 if tonumber(m.quality)~=2 then return nil end
 if newest and (tonumber(m.lastSeen) or 0)<newest-300 then return nil end -- not in the latest scan
 local s=self.db.settings
 local buy=tonumber(l.floor); if not buy or buy<=0 or buy>s.flipMaxBuy then return nil end
 local name=self:FlipName(m); local lower=name:lower(); local matched
 for _,w in ipairs(words) do if lower:find(w,1,true) then matched=w; break end end
 if not matched then return nil end
 local second=tonumber(l.second); local sell,guess
 -- Scans made before 1.9.8 did not record the next price: wait for a new scan.
 if not second and (tonumber(l.listings) or 0)>=2 then return nil end
 if second and second>buy then sell=second-(tonumber(s.sellUndercut) or 1)
 elseif second and second<=buy then return nil -- another listing at the same price: nothing to gain
 else sell=s.flipDefaultSell; guess=true end
 if sell<=buy then return nil end
 local deposit=self:FlipDeposit(m)
 local profit=math.floor(sell*(1-s.ahCut))-buy-deposit
 if profit<s.flipMinProfit then return nil end
 return {marketKey=m.marketKey,itemID=m.itemID,itemLink=m.itemLink,name=name,floor=buy,sell=sell,guess=guess,
  profit=profit,deposit=deposit,listings=tonumber(l.listings) or 0,at=m.lastSeen,word=matched}
end

function M:BuildFlipRows()
 local words=self:FlipWords(); local newest=0
 for _,m in pairs(self.db.market or {}) do local t=tonumber(m.lastSeen) or 0; if t>newest then newest=t end end
 local rows={}
 for _,m in pairs(self.db.market or {}) do
  local ok,row=pcall(self.FlipCandidate,self,m,words,newest>0 and newest or nil)
  if ok and row then rows[#rows+1]=row end
 end
 table.sort(rows,function(a,b) if a.profit~=b.profit then return a.profit>b.profit end return a.name<b.name end)
 self.flipRows=rows; self.flipBuiltFor=(self.db.scanSequence or 0)..'|'..tostring(self.db.settings.flipMaxBuy)..'|'..tostring(self.db.settings.flipMinProfit)..'|'..tostring(self.db.settings.flipWords)
 return rows
end
function M:FlipRows()
 local key=(self.db.scanSequence or 0)..'|'..tostring(self.db.settings.flipMaxBuy)..'|'..tostring(self.db.settings.flipMinProfit)..'|'..tostring(self.db.settings.flipWords)
 if self.flipBuiltFor~=key or not self.flipRows then return self:BuildFlipRows() end
 return self.flipRows
end

-- Screen ---------------------------------------------------------------------
local ROWS=15
local function label(parent,text,x,y,w,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontNormalSmall');f:SetPoint('TOPLEFT',x,y)
 if w then f:SetWidth(w) end;f:SetJustifyH('LEFT');f:SetText(text or '');return f
end
local function button(parent,text,x,y,w,fn,h)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,y);b:SetSize(w,h or 24);b:SetText(text);b:SetScript('OnClick',fn);return b
end
local function edit(parent,x,y,w)
 local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate');e:SetPoint('TOPLEFT',x,y);e:SetSize(w,22);e:SetAutoFocus(false)
 e:SetScript('OnEscapePressed',function(f) f:ClearFocus() end);return e
end

function M:ApplyFlipSettings()
 local s=self.flipScreen; if not s then return end
 local buy=tonumber(s.maxBuy:GetText()); local profit=tonumber(s.minProfit:GetText())
 if buy and buy>0 and buy<=100000 then self.db.settings.flipMaxBuy=math.floor(buy*100+.5) end
 if profit and profit>=0 and profit<=100000 then self.db.settings.flipMinProfit=math.floor(profit*100+.5) end
 local words=s.words:GetText(); if words:match('%S') then self.db.settings.flipWords=words end
 self.page=1; self.selectedRow=nil; self:RefreshUI()
end

function M:InitializeFlipScreen(f)
 local s=CreateFrame('Frame',nil,f);s:SetPoint('TOPLEFT',18,-108);s:SetSize(1004,554);s:Hide();self.flipScreen=s
 local top=self.panel(s,0,0,1004,76)
 label(top,'Green flips: good-suffix greens listed cheap. Buy, then relist just under the next price.',12,-10,980,'GameFontNormal')
 label(top,'Buy at most',12,-44,80,'GameFontHighlight'); s.maxBuy=edit(top,96,-39,60); label(top,'silver',162,-44,40,'GameFontHighlight')
 label(top,'Profit at least',214,-44,96,'GameFontHighlight'); s.minProfit=edit(top,314,-39,60); label(top,'silver',380,-44,40,'GameFontHighlight')
 label(top,'Suffixes',432,-44,60,'GameFontHighlight'); s.words=edit(top,494,-39,330)
 for _,e in ipairs({s.maxBuy,s.minProfit,s.words}) do e:SetScript('OnEnterPressed',function(b) b:ClearFocus();self:ApplyFlipSettings() end) end
 button(top,'Apply',836,-38,72,function() self:ApplyFlipSettings() end)
 button(top,'Reset',914,-38,72,function()
  for _,k in ipairs({'flipMaxBuy','flipMinProfit','flipWords'}) do self.db.settings[k]=self.defaults[k] end
  s.loaded=nil;self:RefreshUI()
 end)
 local res=self.panel(s,0,-84,1004,430);s.results=res
 s.cols={label(res,'Buy for',14,-12,120),label(res,'Item',170,-12,360),label(res,'Sell for',540,-12,130),label(res,'Profit',680,-12,130),label(res,'Listed',820,-12,80)}
 s.rows={}
 for i=1,ROWS do
  local r=CreateFrame('Button',nil,res);r:SetPoint('TOPLEFT',6,-30-(i-1)*26);r:SetSize(990,25)
  r:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight')
  r.sel=r:CreateTexture(nil,'BACKGROUND');r.sel:SetAllPoints();r.sel:SetColorTexture(.32,.15,.5,.45)
  r.icon=r:CreateTexture(nil,'ARTWORK');r.icon:SetSize(20,20);r.icon:SetPoint('LEFT',140,0)
  r.c={label(r,'',8,-7,126,'GameFontHighlight'),label(r,'',166,-7,360,'GameFontHighlight'),label(r,'',534,-7,136,'GameFontHighlight'),
   label(r,'',674,-7,136,'GameFontHighlight'),label(r,'',814,-7,80,'GameFontHighlight')}
  r:SetScript('OnClick',function(b) if b.data then self.selectedRow=b.data;self:RefreshUI() end end)
  r:SetScript('OnDoubleClick',function(b) if b.data then self.selectedRow=b.data;self:ShopSelected(b.data) end end)
  r:SetScript('OnEnter',function(b) self:ShowRowTooltip(b);self:AddFlipTooltip(b.data) end)
  r:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  s.rows[i]=r
 end
 res:EnableMouseWheel(true)
 res:SetScript('OnMouseWheel',function(_,d) self.page=math.max(1,(self.page or 1)-(d>0 and 1 or -1));self:RefreshUI() end)
 s.empty=label(res,'',14,-200,976,'GameFontHighlight');s.empty:SetJustifyH('CENTER')
 s.buy=button(s,'Buy...',0,-522,140,function() if self.selectedRow then self:ShopSelected(self.selectedRow) end end,26)
 button(s,'Price history',148,-522,140,function() self:ShowHistoryWindow(self.selectedRow) end,26)
 s.pageText=label(s,'',600,-528,400,'GameFontHighlightSmall');s.pageText:SetJustifyH('RIGHT')
end

function M:AddFlipTooltip(o)
 if not o or not GameTooltip then return end
 GameTooltip:AddLine(' ')
 GameTooltip:AddDoubleLine('Buy for',self:Money(o.floor),.78,.6,1,1,1,1)
 GameTooltip:AddDoubleLine('Sell for'..(o.guess and ' (guess: no other listing)' or ' (just under next listing)'),self:Money(o.sell),.78,.6,1,1,1,1)
 GameTooltip:AddDoubleLine('AH cut + deposit (est.)',self:Money(math.ceil(o.sell*self.db.settings.ahCut)+o.deposit),.78,.6,1,1,1,1)
 GameTooltip:AddDoubleLine('Profit',self:Money(o.profit),.78,.6,1,.3,.9,.3)
 GameTooltip:AddLine('Double-click to buy. Prices are from the last scan.',.6,.55,.7,true)
 GameTooltip:Show()
end

function M:RenderFlipScreen()
 local s=self.flipScreen; if not s then return end
 s:Show()
 local st=self.db.settings
 if not s.loaded then
  s.maxBuy:SetText(tostring(st.flipMaxBuy/100)); s.minProfit:SetText(tostring(st.flipMinProfit/100)); s.words:SetText(st.flipWords); s.loaded=true
 end
 local rows=self:FlipRows()
 local pages=math.max(1,math.ceil(#rows/ROWS)); self.page=math.min(self.page or 1,pages)
 for i,r in ipairs(s.rows) do
  local o=rows[(self.page-1)*ROWS+i]; r.data=o; r:SetShown(o~=nil)
  if o then
   r.sel:SetShown(self.selectedRow==o)
   r.icon:SetTexture(self:RowItemIcon(o,o.itemID) or 'Interface\\Icons\\INV_Misc_QuestionMark')
   r.c[1]:SetText(self:Coins(o.floor)); r.c[2]:SetText('|cff1eff00'..o.name..'|r')
   r.c[3]:SetText(self:Coins(o.sell)..(o.guess and ' |cff999999?|r' or '')); r.c[4]:SetText('|cff4cff4c'..self:Coins(o.profit)..'|r')
   r.c[5]:SetText(tostring(o.listings))
  end
 end
 local empty=''
 if #rows==0 then
  local any=next(self.db.market or {})~=nil
  empty=any and 'No good-suffix greens are listed under your max buy right now. Run a scan later, or raise "Buy at most".'
   or 'Run a full scan first (VoidMark tab). Flips come from the latest scan.'
 end
 s.empty:SetText(empty); s.empty:SetShown(empty~='')
 s.pageText:SetText(#rows>0 and (#rows..' flips  |  page '..self.page..' / '..pages..'  |  ? = no other listing, sell price is a guess') or '')
 s.buy:SetEnabled(self.selectedRow~=nil and self.ahOpen and true or false)
end
