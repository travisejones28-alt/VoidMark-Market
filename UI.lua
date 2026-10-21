local _,M=...
local tabs={{'OVERVIEW','market'},{'BROWSE','browse'},{'SNIPER','opportunities'},{'SHOPPING','shopping'},
 {'SELL','selling'},{'INVESTMENTS','investments'},{'BANKER','banker'},{'LEDGER','ledger'},{'SETTINGS','settings'}}
local function label(parent,text,x,y,w,font)
  local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontNormalSmall'); f:SetPoint('TOPLEFT',x,y)
  if w then f:SetWidth(w) end; f:SetJustifyH('LEFT'); f:SetText(text); return f
end
local function button(parent,text,x,y,w,fn)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate'); b:SetPoint('TOPLEFT',x,y); b:SetSize(w,26); b:SetText(text); b:SetScript('OnClick',fn); return b
end
local function edit(parent,x,y,w,text)
  local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate'); e:SetPoint('TOPLEFT',x,y); e:SetSize(w,24); e:SetAutoFocus(false)
  e:SetText(text or ''); e:SetScript('OnEscapePressed',function(f) f:ClearFocus() end); return e
end
function M:SetView(view)
  self.view=view; self.page=1; if self.window then self.window:Show() end
  if view=='selling' then self:RefreshInventory() elseif view=='browse' then self:BuildBrowseRows(self.db.settings.filter or '') end; self:RefreshUI()
end
function M:ToggleUI() if self.window:IsShown() then self.window:Hide() else self.window:Show(); self:RefreshUI() end end
function M:InitializeUI()
  if self.window then return end
  local f=CreateFrame('Frame','VoidMarkMarketWindow',UIParent,'BackdropTemplate'); self.window=f
  f:SetSize(1040,680); f:SetPoint('CENTER'); f:SetFrameStrata('MEDIUM'); f:SetToplevel(true); f:SetMovable(true); f:EnableMouse(true)
  f:SetClampedToScreen(true); f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart',function(w) w:StartMoving() end); f:SetScript('OnDragStop',function(w) w:StopMovingOrSizing() end)
  f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
  f:SetBackdropColor(0.025,0.022,0.04,0.97); f:SetBackdropBorderColor(0.45,0.3,0.7,1)
  if UIParent.GetWidth then f:SetScale(math.min(1,(UIParent:GetWidth()-30)/1040,(UIParent:GetHeight()-30)/680)) end
  label(f,'VOIDMARK MARKET',18,-16,300,'GameFontNormalLarge')
  self.modeLabel=label(f,'SAFE MODE ON',365,-19,455)
  button(f,'TRANSFER',860,-12,125,function() self:ShowTransferWindow() end)
  button(f,'X',995,-12,26,function() f:Hide() end)
  for i,v in ipairs(tabs) do local tab=v[2]; button(f,v[1],18+(i-1)*111,-48,108,function() self:SetView(tab) end) end
  self.status=label(f,'',18,-84,995)
  self.toolbar=CreateFrame('Frame',nil,f); self.toolbar:SetPoint('TOPLEFT',18,-109); self.toolbar:SetSize(1000,34)
  self.scanButton=button(self.toolbar,'FULL SCAN',0,0,110,function() self:RequestFreshScan() end)
  self.cachedButton=button(self.toolbar,'CACHED',116,0,88,function() self:AnalyzeCachedSnapshot() end)
  self.filter=edit(self.toolbar,252,-1,147,self.db.settings.filter); label(self.toolbar,'Find:',211,-7,40)
  self.filter:SetScript('OnTextChanged',function(e)
    self.db.settings.filter=e:GetText(); self.page=1
    if self.view=='browse' then self:BuildBrowseRows(self.db.settings.filter) end
    self:RefreshUI()
  end)
  self.sortButton=button(self.toolbar,'SORT: SCORE',405,0,116,function()
    local sorts={'score','profit','roi','confidence','liquidity','discount','ask','name'}; local current=self.db.settings.sort
    for i,v in ipairs(sorts) do if v==current then self.db.settings.sort=sorts[i%#sorts+1]; break end end
    self:RefreshUI()
  end)
  button(self.toolbar,'<',525,0,32,function() self.page=math.max(1,(self.page or 1)-1); self:RefreshUI() end)
  button(self.toolbar,'>',563,0,32,function() self.page=(self.page or 1)+1; self:RefreshUI() end)
  self.pageText=label(self.toolbar,'',604,-7,93)
  button(self.toolbar,'BUY QUEUE',702,0,92,function() self:SetView('review') end)
  button(self.toolbar,'MY AUCTIONS',798,0,115,function() self:SetView('my auctions') end)
  button(self.toolbar,'DIAG',919,0,78,function() self:SetView('diagnostics') end)
  self.tableFrame=CreateFrame('Frame',nil,f); self.tableFrame:SetPoint('TOPLEFT',18,-151); self.tableFrame:SetSize(1000,340)
  self.headings={}; self.rows={}
  local widths={270,105,105,110,75,55,110,120}; local x=0
  for i,w in ipairs(widths) do self.headings[i]=label(self.tableFrame,'',x,-2,w); x=x+w end
  for r=1,12 do
    local b=CreateFrame('Button',nil,self.tableFrame); self.rows[r]=b; b:SetPoint('TOPLEFT',0,-25-(r-1)*25); b:SetSize(1000,25)
    b:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight'); b.cols={}; local cx=0
    for i,w in ipairs(widths) do b.cols[i]=label(b,'',cx,-6,w-5,'GameFontHighlightSmall'); cx=cx+w end
    b:SetScript('OnClick',function(row)
      if not row.data then return end
      self.selectedRow=row.data
      if self.view=='opportunities' then self:SelectOpportunity(row.data)
      elseif self.view=='review' and row.data.opportunity then self:SelectOpportunity(row.data.opportunity)
      elseif self.view=='my auctions' then self:AnalyzeOwnedLive(row.data)
      else self:RefreshUI() end
    end)
  end
  self.detail=label(f,'',18,-493,998,'GameFontHighlightSmall'); self.detail:SetHeight(125); self.detail:SetJustifyV('TOP')
  self.contentScroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate')
  self.contentScroll:SetPoint('TOPLEFT',18,-151); self.contentScroll:SetSize(976,465)
  local child=CreateFrame('Frame',nil,self.contentScroll); child:SetSize(972,460); self.contentScroll:SetScrollChild(child)
  self.content=label(child,'',0,0,960,'GameFontHighlightSmall'); self.content:SetJustifyV('TOP')
  self.statsFrame=CreateFrame('Frame',nil,f); self.statsFrame:SetPoint('TOPLEFT',18,-151); self.statsFrame:SetSize(998,198)
  self.statValues={}
  local cards={{'CURRENT GOLD',1},{'TRADING CAPITAL',2},{'COST BASIS',3},{'EST. LIQUIDATION',4},{'REALIZED RESULT',5},{'UNRESOLVED SPEND',6}}
  for i,entry in ipairs(cards) do
    local col=(i-1)%3; local r=math.floor((i-1)/3)
    local card=CreateFrame('Frame',nil,self.statsFrame,'BackdropTemplate')
    card:SetPoint('TOPLEFT',col*334,-r*98); card:SetSize(320,90)
    card:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=12})
    card:SetBackdropColor(0.055,0.04,0.095,0.97);card:SetBackdropBorderColor(0.34,0.22,0.55,0.9)
    label(card,entry[1],12,-10,292)
    self.statValues[i]=label(card,'--',12,-38,292,'GameFontNormalLarge')
  end
  self.watchFrame=CreateFrame('Frame',nil,f);self.watchFrame:SetPoint('TOPLEFT',18,-533);self.watchFrame:SetSize(990,82)
  label(self.watchFrame,'Watch by item ID (base variant):',0,-2,220)
  self.watchItem=edit(self.watchFrame,220,2,112,'')
  label(self.watchFrame,'Target gold:',348,-2,95)
  self.watchTarget=edit(self.watchFrame,440,2,94,'')
  button(self.watchFrame,'SAVE TARGET',546,2,125,function()
    local raw=self.watchItem:GetText()
    local id=tonumber(raw);local market=id and self.db.market[id] or nil
    local selected=self.selectedRow
    if selected and selected.marketKey and (raw=='' or tostring(selected.itemID)==raw) then
      market=self.db.market[selected.marketKey]
    end
    local rawTarget=self.watchTarget:GetText()
    local amount=rawTarget~='' and tonumber(rawTarget) or nil
    if rawTarget~='' and not amount then self:Print('Enter a numeric gold price target');return end
    local copper=amount and math.floor(amount*10000+0.5) or nil
    local ok,why=self:SetWatch(market and market.marketKey,copper)
    self:Print(ok and 'Watch target saved for this economy' or why)
  end)
  button(self.watchFrame,'REMOVE SELECTED',680,2,160,function()
    if not self.selectedRow or not self.selectedRow.marketKey then self:Print('Select a watched item first');return end
    self:RemoveWatch(self.selectedRow.marketKey);self.selectedRow=nil
  end)
  label(self.watchFrame,'Targets are observational only; stale auctions never trigger a buy. Purchases require live validation and clicks.',0,-41,974)
  self.action=CreateFrame('Frame',nil,f); self.action:SetPoint('BOTTOMLEFT',18,18); self.action:SetSize(1000,28)
  self.quantity=edit(self.action,83,-1,80,'1'); label(self.action,'Quantity:',0,-7,80)
  self.revalidateButton=button(self.action,'REVALIDATE',180,0,130,function() self:RevalidateSelected(self.quantity:GetText()) end)
  self.executeButton=button(self.action,'EXECUTE',318,0,130,function() self:ExecuteClicked() end)
  self.confirmButton=button(self.action,'CONFIRM QUOTE',456,0,155,function() self:ConfirmClicked() end)
  self.cancelQuoteButton=button(self.action,'DISCARD QUOTE',619,0,150,function()
    if self.execution.state=='quoting' or self.execution.state=='quoted' then self:InvalidateQuote('Quote discarded') end
  end)
  self.addReviewButton=button(self.action,'SAVE TO QUEUE',778,0,168,function()
    local ok,why=self:QueuePurchaseReview(self.execution.opportunity)
    self:Print(ok and 'Opportunity added to player review queue' or why)
  end)
  self.ledgerAction=CreateFrame('Frame',nil,f); self.ledgerAction:SetPoint('BOTTOMLEFT',18,18); self.ledgerAction:SetSize(1000,28)
  button(self.ledgerAction,'BOOK REVIEWED SALE',0,0,190,function()
    if not self:BookSale(self.selectedRow) then self:Print('Select an unbooked verified invoice with one exact market match') end
  end)
  button(self.ledgerAction,'MARK BUY CONFIRMED',200,0,200,function() self:ReviewPending(self.selectedRow,true) end)
  button(self.ledgerAction,'MARK BUY FAILED',410,0,170,function() self:ReviewPending(self.selectedRow,false) end)
  self.sellAction=CreateFrame('Frame',nil,f);self.sellAction:SetPoint('BOTTOMLEFT',18,18);self.sellAction:SetSize(1000,28)
  self.sellStrategyButton=button(self.sellAction,'STRATEGY',0,0,180,function()
    local strategies=self:GetSellStrategies();local current=self.db.settings.sellStrategy;local idx=1
    for i,v in ipairs(strategies) do if v==current then idx=i%#strategies+1;break end end
    self:SetSellStrategy(strategies[idx])
  end)
  label(self.sellAction,'Minimum gold/unit:',195,-7,130)
  self.sellFloorEdit=edit(self.sellAction,330,-1,110,'')
  button(self.sellAction,'SAVE MINIMUM',455,0,145,function()
    local r=self.selectedRow
    if not r or not r.marketKey then self:Print('Select a bag item with market data');return end
    local raw=self.sellFloorEdit:GetText()
    local g=tonumber(raw)
    if raw~='' and (not g or g<=0 or g>1e8) then self:Print('Minimum must be positive gold (blank to clear)');return end
    local ok,why=self:SetSellFloor(r.marketKey,raw~='' and math.floor(g*10000+0.5) or nil)
    self:Print(ok and 'Minimum updated; advisory prices recalculated' or why)
  end)
  button(self.sellAction,'REFRESH BAGS',612,0,144,function()self:RefreshInventory()end)
  self.ownedRefresh=button(f,'REFRESH MY AUCTIONS',18,-628,210,function() self:RequestOwnedAuctionsDiagnostic() end)
  self.reviewRemove=button(f,'REMOVE QUEUED ITEM',18,-628,200,function()
    if self.selectedRow and self.selectedRow.marketKey then
      if self:RemovePurchaseReview(self.selectedRow.marketKey) then self.selectedRow=nil end
    else self:Print('Select a queue entry first') end
  end)
  self.settingsFrame=CreateFrame('Frame',nil,f); self.settingsFrame:SetPoint('TOPLEFT',18,-151); self.settingsFrame:SetSize(998,460)
  local settings={
    {'maxTransaction','Maximum transaction (gold)',10000},{'maxItemSpend','Maximum per-item exposure (gold)',10000},
    {'maxExposure','Maximum portfolio exposure (gold)',10000},{'maxQuantity','Maximum quantity',1},
    {'minProfit','Minimum expected profit (silver)',100},{'minROI','Minimum ROI (%)',0.01},
    {'minConfidence','Minimum confidence (0-100)',1},{'minLiquidity','Minimum inferred liquidity (0-100)',1},
    {'riskTolerance','Maximum volatility (%)',0.01},{'depositReserve','Resale deposit allowance/unit (silver)',100},
    {'ahCut','AH cut (%) - verify current AH',0.01},{'maxDataAge','Maximum model age (minutes)',60},
    {'minGoldReserve','Minimum liquid gold reserve (gold)',10000},
    {'sellMinMargin','Known-cost minimum margin (%)',0.01}}
  self.settingFields={}
  for i,s in ipairs(settings) do
    local col=(i-1)%2; local row=math.floor((i-1)/2); local x=col*495
    label(self.settingsFrame,s[2],x,-row*52,355)
    local e=edit(self.settingsFrame,x+365,-row*52+3,100,tostring(self.db.settings[s[1]]/s[3]))
    self.settingFields[#self.settingFields+1]={edit=e,key=s[1],factor=s[3]}
  end
  button(self.settingsFrame,'APPLY LIMITS',0,-352,155,function()
    local values={}
    for _,s in ipairs(self.settingFields) do
      local n=tonumber(s.edit:GetText())
      if not n or n<0 or n>1e9 then self:Print('Use nonnegative numeric limits'); return end
      values[s.key]=n*s.factor
    end
    if values.ahCut>0.30 or values.minConfidence>100 or values.minLiquidity>100 or values.riskTolerance>2 or values.maxDataAge>86400*7 then self:Print('One or more limits exceed supported ranges'); return end
    if values.sellMinMargin>2 then self:Print('Sell margin must be 0%-200%');return end
    values.maxQuantity=math.floor(values.maxQuantity)
    for k,v in pairs(values) do self.db.settings[k]=v end
    if self.execution.state=='quoted' then self:InvalidateQuote('Limits changed; revalidate')
    elseif self.execution.state=='ready' then self.execution.state='stale'; self.execution.message='Limits changed; revalidate' end
    self:RebuildOpportunities(); self:RefreshUI()
  end)
  self.safe=CreateFrame('CheckButton',nil,self.settingsFrame,'UICheckButtonTemplate'); self.safe:SetPoint('TOPLEFT',190,-349); self.safe:SetSize(28,28)
  label(self.settingsFrame,'SAFE MODE (starts ON every login)',223,-357,450)
  self.safe:SetChecked(true); self.safe:SetScript('OnClick',function(c)
    self.db.settings.safeMode=c:GetChecked() and true or false; self.safeMode=self.db.settings.safeMode
    if self.safeMode and (self.execution.state=='quoted' or self.execution.state=='quoting') then self:InvalidateQuote('Safe Mode enabled') end
    self:RefreshUI()
  end)
  self.minimapToggle=CreateFrame('CheckButton',nil,self.settingsFrame,'UICheckButtonTemplate')
  self.minimapToggle:SetPoint('TOPLEFT',0,-386); self.minimapToggle:SetSize(28,28)
  label(self.settingsFrame,'Show minimap icon',34,-394,240)
  self.minimapToggle:SetChecked(not (self.root.settings.minimap and self.root.settings.minimap.hide))
  self.minimapToggle:SetScript('OnClick',function(c)
    self:SetMinimapIconVisible(c:GetChecked() and true or false)
  end)
  label(self.settingsFrame,'Safe Mode always starts ON. Each purchase requires a click; reserve protects liquid gold.\nDeposits and liquidity are estimates, not proof of sales. Cross-client sharing remains disabled.',0,-424,970)
  self.view='market'; self.page=1; self:RefreshUI(); f:Hide() -- Keep Market closed on login/reload until opened by the user.
end
function M:ShowReport()
  if not self.reportWindow then
    local f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate'); self.reportWindow=f; f:SetSize(800,570); f:SetPoint('CENTER'); f:SetFrameStrata('DIALOG')
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'}); f:SetBackdropColor(0.02,0.02,0.02,1)
    button(f,'CLOSE',665,-12,115,function() f:Hide() end)
    label(f,'Diagnostics - Ctrl+A, Ctrl+C to copy',18,-18,600)
    local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate'); scroll:SetPoint('TOPLEFT',18,-52); scroll:SetSize(745,490)
    local e=CreateFrame('EditBox',nil,scroll); e:SetMultiLine(true); e:SetFontObject('ChatFontNormal'); e:SetWidth(735); e:SetAutoFocus(false); e:SetScript('OnEscapePressed',function() f:Hide() end); scroll:SetScrollChild(e); self.reportEdit=e
  end
  self.reportEdit:SetText(self:BuildTextReport()); self.reportWindow:Show(); self.reportEdit:SetFocus(); self.reportEdit:HighlightText()
end
function M:RenderUI()
  self.uiDirty=false; if not self.window or not self.window:IsShown() then return end
  local view=self.view or 'market'; local s=self.db.settings
  self.modeLabel:SetText(s.safeMode and '|cff72e7aaSAFE MODE ON - no transactions|r' or '|cffffa250TRADING ENABLED - real clicks required|r')
  self.status:SetText('AH '..(self.ahOpen and 'OPEN' or 'CLOSED')..' | '..self.scanState.status..' | full scan cooldown '..self:FormatDuration(self:GetSecondsUntilFreshScanAllowed()))
  self.toolbar:Show(); self.tableFrame:Hide(); self.detail:Hide(); self.contentScroll:Hide(); self.settingsFrame:Hide(); self.action:Hide(); self.ledgerAction:Hide(); self.ownedRefresh:Hide(); self.reviewRemove:Hide(); self.sellAction:Hide(); self.watchFrame:Hide(); self.statsFrame:Hide()
  self.filter:SetShown(view=='opportunities' or view=='browse'); self.sortButton:SetShown(view=='opportunities'); self.sortButton:SetText('SORT: '..s.sort:upper())
  self.scanButton:SetEnabled(self.ahOpen and not self.scanState.running); self.cachedButton:SetEnabled(self.ahOpen and not self.scanState.running)
  if view=='settings' then self.settingsFrame:Show(); self.safe:SetChecked(s.safeMode); self.minimapToggle:SetChecked(not (s.minimap and s.minimap.hide)); return end
  if view=='market' or view=='banker' then
    local data=self:GetBankerSummary();local p=data.portfolio
    local values={data.gold,data.available,p.cost,p.estimatedNet,data.realized,data.pending}
    for i,v in ipairs(values) do self.statValues[i]:SetText(self:Money(v)) end
    self.statsFrame:Show()
    self.contentScroll:ClearAllPoints();self.contentScroll:SetPoint('TOPLEFT',18,-361);self.contentScroll:SetSize(976,250)
  else
    self.contentScroll:ClearAllPoints();self.contentScroll:SetPoint('TOPLEFT',18,-151);self.contentScroll:SetSize(976,465)
  end
  local text
  if view=='execution' then
    self.action:Show(); local x=self.execution; local m=x.market
    local lines={'|cffffffffEXECUTION / '..x.state:upper()..'|r',x.message,'',m and m.name or 'Select an opportunity first.'}
    if m then
      lines[#lines+1]='Historical ask '..self:Money(m.latest.floor)..' | fair '..self:Money(m.fairValue)..' | meaningful floor '..self:Money(m.latest.meaningfulFloor or m.latest.q10)
      lines[#lines+1]='Confidence '..tostring(m.confidence)..' | inferred liquidity '..tostring(m.activity)..' | '..m.observations..' observations'
      lines[#lines+1]=m.modelReason or ''
      local p=x.opportunity.parts
      if p then lines[#lines+1]=string.format('Rank %d: profit +%.1f, ROI +%.1f, confidence +%.1f, liquidity +%.1f, depth +%.1f, volatility -%.1f, capital -%.1f',x.opportunity.score,p.profit,p.roi,p.confidence,p.liquidity,p.depth,p.risk,p.exposure) end
      lines[#lines+1]='Snapshot limits: '..(x.opportunity.pass and 'passed at analysis time' or table.concat(x.opportunity.blocks or {},'; '))
      if x.live then
        local e=x.live.economics
        lines[#lines+1]='\nLIVE: '..x.live.quantity..' units | total '..self:Money(x.live.cost)..' | expected net '..self:Money(e.net)..' | ROI '..self:PercentText(e.roi)
        lines[#lines+1]='Gross estimate '..self:Money(e.gross)..' | cut '..self:Money(e.fee)..' | deposit allowance '..self:Money(e.depositReserve)
        lines[#lines+1]=x.commodity and 'Commodity: EXECUTE requests a quote; CONFIRM QUOTE purchases it.' or ('Regular item: one full auction #'..tostring(x.live.auctionID))
        lines[#lines+1]='Model '..e.kind..(e.kind=='vendor' and ': vendor spread, no resale fees' or ': resale estimates do not guarantee a sale')
      end
      lines[#lines+1]='\nWhy: '..table.concat(m.reasons or {},'; ')
      lines[#lines+1]='Risks: '..table.concat(m.risks or {},'; ')
    end
    self.revalidateButton:SetEnabled(not self.persistenceBlocked and self.ahOpen and m~=nil and not self:HasUnresolvedPurchase() and x.state~='quoting' and x.state~='quoted' and x.state~='validating')
    self.executeButton:SetEnabled(not self.persistenceBlocked and not s.safeMode and self.ahOpen and x.state=='ready' and not self:HasUnresolvedPurchase())
    self.confirmButton:SetEnabled(not s.safeMode and x.state=='quoted')
    self.cancelQuoteButton:SetEnabled(x.state=='quoted' or x.state=='quoting')
    self.addReviewButton:SetEnabled(x.opportunity~=nil and not self.persistenceBlocked)
    text=table.concat(lines,'\n')
  elseif view=='diagnostics' then text=self:BuildTextReport()
  elseif view=='market' then
    local scan=self.db.latestScan; local stats=self.db.marketStats or {}; local totals=self:LedgerTotals()
    text='|cffffffffLOCAL MARKET TERMINAL|r\n\n'..#(self.marketIndex or {})..' markets | '..#self.db.opportunities..' ranked candidates\nEconomy: '..self.economyID..'\n\n'
    if scan then text=text..string.format('Last scan %s\nRows %d | valid %d | invalid %d | incomplete %d\nMarkets %d | total supply %d | elapsed %s ms | generation #%s\n\n',date('%Y-%m-%d %H:%M',scan.completedAt or time()),scan.rawRows or 0,scan.auctionsProcessed or 0,scan.invalidRecords or 0,scan.incompleteRecords or 0,scan.uniqueItems or 0,scan.totalQuantity or 0,tostring(scan.processingMS),tostring(scan.marketScanID)) end
    if scan and scan.deferredRows then text=text..string.format('Item data: %d deferred | %d recovered | %d unresolved\n\n',scan.deferredRows,scan.recoveredRows or 0,scan.unresolvedRows or 0) end
    text=text..self:BuildFullScanReport()..'\n\n'
    text=text..'Cost-matched realized '..self:Money(totals.realized)..' | verified net sale revenue '..self:Money(totals.revenue)..'\n'..
      'Portfolio liquidation is an ESTIMATE for fresh, modeled positions only. Missing price history has no assumed value.\n'..
      'Scan results are advisory. Select SNIPER for live revalidation; SELL uses the native Auction House for posting.\n'..
      'Use BANKER to review scan changes and SHOPPING for saved price targets. /vmm report opens diagnostics.'
  elseif view=='banker' then
    local summary=self:GetBankerSummary()
    local banker=summary.scanner or {}
    local scan=summary.latestScan
    local lines={'|cffffffffBANKER WORKSTATION — PLAYER-CONTROLLED|r','',
      'Liquid reserve '..self:Money(summary.reserve)..' | Available after reserve/pending '..self:Money(summary.available),
      'Portfolio positions '..summary.portfolio.positions..' | Unpriced cost '..self:Money(summary.portfolio.unvaluedCost),
      'Estimated unrealized net '..self:Money(summary.portfolio.unrealized)..' (fresh models only)',
      'Confirmed realized result '..self:Money(summary.realized)..' | Unresolved spend '..self:Money(summary.pending),'',
      'Latest published snapshot: '..(scan and date('%Y-%m-%d %H:%M',scan.completedAt or time()) or 'none'),
      'New passing opportunities since previous FRESH completed scan: '..#(banker.new or {})}
    for i,o in ipairs(banker.new or {}) do
      if i>12 then lines[#lines+1]='...more candidates on SNIPER';break end
      lines[#lines+1]=tostring(o.name)..' | rank '..tostring(o.score)
    end
    lines[#lines+1]=''
    lines[#lines+1]='Cached analyses do not create independent history or new opportunity alerts.'
    lines[#lines+1]='No unattended scans or transactions. Open AH and click FULL SCAN when cooldown permits.'
    text=table.concat(lines,'\n')
  else
    local source,headers={},{'Name','Ask','Fair','Net','ROI','Score','Confidence','Liquidity'}
    if view=='opportunities' then
      source=self:GetSniperRows(s.filter,s.sort)
      headers={'Item / status','Ask','Fair','Net','ROI','Score','Confidence','Risk'}
    elseif view=='review' then
      source=self:GetPurchaseReviewRows();self.reviewRemove:Show()
      headers={'Saved candidate','Old ask','Latest ask','Fair','ROI','','Confidence','State'}
    elseif view=='browse' then
      source=self.browseRows or {}; headers={'Cached item','Item ID','Ask/unit','Fair','Median 7d','Median 30d','Confidence','State'}
    elseif view=='shopping' then
      source=self:GetWatchRows();headers={'Watched item','Item ID','Ask/unit','Fair','Target','','Confidence','State'}
      self.watchFrame:Show()
    elseif view=='investments' then
      source=self:GetPortfolioRows();headers={'Owned investment','Quantity','Cost basis','Net est.','Unrealized','ROI','','State'}
    elseif view=='selling' then source=self.sellingRows; self.sellAction:Show();self.sellStrategyButton:SetText('MODE: '..(s.sellStrategy or 'competitive'):upper()); headers={'Inventory','Quantity','Suggest/unit','Fair','Basis/unit','Net est.','Confidence','State'}
    elseif view=='my auctions' then source=self.ownedRows; self.ownedRefresh:Show(); headers={'My listing','Quantity','My unit','Competitor','Time left','','',''}
    elseif view=='ledger' then
      self.ledgerAction:Show(); headers={'Event / item','Quantity','Cost','Revenue','State','ID','Evidence',''}
      for i=#self.db.ledger,1,-1 do source[#source+1]=self.db.ledger[i] end
      -- Unresolved purchases remain selectable even after compact history pruning.
      for _,p in pairs(self.db.pending) do
        local found=false; for _,e in ipairs(source) do if e==p then found=true; break end end
        if not found then table.insert(source,1,p) end
      end
    end
    local pages=math.max(1,math.ceil(#source/12)); self.page=math.min(self.page or 1,pages)
    self.pageText:SetText(self.page..' / '..pages..' ('..#source..')')
    self.tableFrame:Show(); self.detail:Show()
    for i,h in ipairs(headers) do self.headings[i]:SetText(h) end
    for i,row in ipairs(self.rows) do
      local o=source[(self.page-1)*12+i]; row.data=o; row:SetShown(o~=nil)
      if o then
        local cells
        if view=='opportunities' then cells={(o.pass and '' or '|cffff9a9a[BLOCKED]|r ')..(o.kind=='vendor' and '|cff72e7aa[VENDOR]|r ' or '')..o.name,
          self:Money(o.floor),self:Money(o.fairValue),self:Money(o.economics.net),self:PercentText(o.economics.roi),
          o.score,o.confidence,o.risk}
        elseif view=='review' then cells={o.name,self:Money(o.snapshotAsk),o.ask>0 and self:Money(o.ask) or 'Missing',
          self:Money(o.fair),self:PercentText(o.roi),'',o.confidence,o.status}
        elseif view=='browse' then cells={o.name,o.itemID,o.floor>0 and self:Money(o.floor) or 'No local ask',
          self:Money(o.fair),o.median7 and self:Money(o.median7) or '--',o.median30 and self:Money(o.median30) or '--',o.confidence,o.status}
        elseif view=='shopping' then cells={o.name,o.itemID,self:Money(o.floor),self:Money(o.fair),o.target and self:Money(o.target) or 'Any','',o.confidence,o.status}
        elseif view=='investments' then cells={o.name,o.quantity,self:Money(o.cost),o.estimatedNet and self:Money(o.estimatedNet) or 'Unknown',
          o.unrealized and self:Money(o.unrealized) or 'Unknown',o.roi and self:PercentText(o.roi) or 'N/A','',o.status}
        elseif view=='selling' then cells={o.name,o.quantity,o.price and self:Money(o.price) or 'No quote',o.fair and self:Money(o.fair) or '--',o.basisUnit and self:Money(o.basisUnit) or 'Unknown',o.estimatedNet and self:Money(o.estimatedNet) or '--',o.confidence,o.status}
        elseif view=='my auctions' then cells={o.name,o.quantity,self:Money(o.unit),o.competition and self:Money(o.competition) or '?',
          tostring(o.timeLeft or '?'),o.action or 'INSPECT','',''}
        else cells={(o.kind or '')..': '..tostring(o.name or o.auctionID or ''),o.quantity or '',o.cost and self:Money(o.cost) or '',o.gross and self:Money(o.gross) or '',o.booked and 'booked' or o.status,o.id,o.evidence or '',''} end
        for j,c in ipairs(cells) do row.cols[j]:SetText(tostring(c)) end
      end
    end
    local o=self.selectedRow
    if view=='opportunities' then self.detail:SetText('Select a row to inspect economics and revalidate live prices. Vendor opportunities have a separate model.\nResale rankings weigh absolute profit, ROI, confidence, inferred liquidity, depth, volatility and capital exposure.\nA snapshot opportunity may fail current limits or disappear before you buy. Live prices expire after 10 seconds.')
    elseif view=='review' then
      self.detail:SetText('This is an advisory purchase REVIEW QUEUE, not a transaction queue.\nItems with REVALIDATE can be clicked to inspect, but the live purchase still needs complete search validation and a permitted user click.\nRECHECK items have stale/blocked/missing market data. They remain saved until you remove them.')
    elseif view=='shopping' then
      self.detail:SetText('Select an item to update or remove its target. Enter a base item ID and target in gold below.\nTargets only flag fresh cached asking prices; no automatic purchases.')
    elseif view=='investments' then
      local _,p=self:GetPortfolioRows()
      self.detail:SetText('Capital at known cost '..self:Money(p.cost)..' | modeled liquidation after estimated fees '..self:Money(p.estimatedNet)..
        '\nEstimated unrealized '..self:Money(p.unrealized)..' | not currently priceable '..self:Money(p.unvaluedCost)..
        '\nOnly purchases with tracked acquisition basis are included. Estimates are not confirmed sales.')
    elseif view=='selling' then
      if o and o.bag~=nil then
        self.detail:SetText('Bag '..o.bag..' / slot '..o.slot..' | '..tostring(o.status)..' | '..tostring(o.strategy or 'No strategy')..
          '\n'..(o.price and ('Price per unit '..self:Money(o.price)..' | Gross '..self:Money(o.gross)..' | estimated AH cut '..self:Money(o.estimatedCut)..' | deposit allowance '..self:Money(o.depositAllowance)) or 'No reliable pricing available')..
          '\n'..(o.profit and ('Estimated net profit '..self:Money(o.profit)..' | ROI '..self:PercentText(o.roi or 0)) or 'Profit unavailable: basis is not fully known')..
          '\n'..tostring(o.reason or '')..'\nAdvisory only. Confirm the current listing, posting deposit and duration in the native AH.')
      else self.detail:SetText('Select a bag item for its price, cost basis and risk. No post is made by this panel.') end
    elseif view=='my auctions' then
      self.detail:SetText(o and ('Own auction #'..tostring(o.auctionID)..' | '..tostring(o.action or 'INSPECT')..
        '\n'..tostring(o.reason or 'Select a row to fetch live competition.')..
        '\n'..(o.repriceDifference and ('Gross reduction on reprice '..self:Money(o.repriceDifference)) or 'No repricing economics available')..
        '\nCancel/repost is advisory only; confirm native AH deposit, fees, time remaining and live sale demand.') or
        'Select an auction to inspect the live competitors. No cancel/post action is automatic.')
    elseif view=='browse' then
      self.detail:SetText('Search cached market history by name. '..tostring(#source)..' cached results shown (maximum 300).'..
        '\nThe 7/30-day medians are scan medians, not verified sales. SHARED* prices are advisory only.\nSelect a local item, then SHOPPING to set a target. Cached prices are not live quotes.')
    elseif view=='ledger' then
      local t=self:LedgerTotals()
      self.detail:SetText('Cost-matched realized '..self:Money(t.realized)..' | ROI '..self:PercentText(t.roi)..' | fees '..self:Money(t.fees)..' | uncosted revenue '..self:Money(t.uncostedRevenue)..'\n'..(o and (tostring(o.evidence)..'\n'..tostring(o.name or '')..' | market '..tostring(o.marketKey)..' | deposit refund '..self:Money(o.depositRefund)) or 'Select an invoice or unresolved order.')..'\nMailbox invoices are observed facts, but have no unique ID. Review identity before BOOK REVIEWED SALE.\nPurchase cost uses moving average. Unknown cost is excluded from realized profit; manually reported outcomes are labeled.')
    else self.detail:SetText(o and (tostring(o.name)..'\n'..tostring(o.reason or '')..'\nAdvisory only. Verify live price and deposit in the native auction window.') or 'Select a row for details. Posting and cancellation use the native auction window.') end
    return
  end
  self.contentScroll:Show(); self.content:SetText(text or ''); self.content:SetHeight(math.max(450,self.content:GetStringHeight()+20))
end

function M:ShowTransferWindow()
  if not self.transferWindow then
    local f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');self.transferWindow=f
    f:SetSize(850,580);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetMovable(true);f:EnableMouse(true)
    f:RegisterForDrag('LeftButton')
    f:SetScript('OnDragStart',function(w)w:StartMoving()end)
    f:SetScript('OnDragStop',function(w)w:StopMovingOrSizing()end)
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=14})
    f:SetBackdropColor(0.035,0.026,0.065,0.98);f:SetBackdropBorderColor(0.48,0.25,0.75,1)
    label(f,'MANUAL TWO-ACCOUNT MARKET TRANSFER',18,-14,600,'GameFontNormalLarge')
    button(f,'CLOSE',746,-11,87,function()f:Hide()end)
    label(f,'EXPORT copies up to 100 fresh local observations. Paste via Ctrl+A / Ctrl+C on one account, Ctrl+V on the other.',18,-48,810)
    label(f,'Matching realm and faction required. Imports are ADVISORY and never authorize buying or create historical observations.',18,-70,810)
    local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',18,-108);scroll:SetSize(794,395)
    local e=CreateFrame('EditBox',nil,scroll);e:SetMultiLine(true);e:SetFontObject('ChatFontNormal')
    e:SetWidth(768);e:SetAutoFocus(false);e:SetScript('OnEscapePressed',function()f:Hide()end)
    scroll:SetScrollChild(e);self.transferEdit=e
    self.transferStatus=label(f,'No data transferred',18,-521,810)
    button(f,'GENERATE EXPORT',18,-537,180,function()
      local raw,err=self:ExportMarketTransfer()
      if raw then e:SetText(raw);e:SetFocus();e:HighlightText();self.transferStatus:SetText('Export ready; Ctrl+C to copy')
      else self.transferStatus:SetText(err or 'Export failed') end
    end)
    button(f,'IMPORT PASTED TEXT',211,-537,195,function()
      local ok,msg=self:ImportMarketTransfer(e:GetText())
      self.transferStatus:SetText((ok and '|cff72e7aa' or '|cffff7777')..tostring(msg)..'|r')
    end)
    button(f,'SELECT ALL',419,-537,125,function()e:SetFocus();e:HighlightText()end)
  end
  self.transferWindow:Show()
end
