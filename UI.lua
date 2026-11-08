local _,M=...
local tabs={{'SHOPPING','browse'},{'SELLING','selling'},{'CANCELING','my auctions'},{'SCANNING','market'},
 {'HISTORY','banker'},{'VENDOR','vendor'},{'CRAFTING','crafting'},{'SETTINGS','settings'},{'TOOLS','tools'}}
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
  if self.view~=view and view~='shopping' then self.selectedRow=nil end
  self.view=view; self.page=1; if self.window then self.window:Show() end
  if self.RememberAuctionView then self:RememberAuctionView(view) end
  if view=='goldmaking' and self.RebuildGoldmaking then self:RebuildGoldmaking() end
  if view=='selling' or view=='post review' then self:RefreshInventory()
  elseif view=='browse' then self:BuildBrowseRows(self.db.settings.filter or '') end; self:RefreshUI()
end
function M:ToggleUI() if self.window:IsShown() then self:CloseMarketWindow() else self.window:Show(); self:RefreshUI() end end
function M:InitializeUI()
  if self.window then return end
  local f=CreateFrame('Frame','VoidMarkMarketWindow',UIParent,'BackdropTemplate'); self.window=f
  f:SetSize(1040,680); f:SetPoint('CENTER'); f:SetFrameStrata('MEDIUM'); f:SetToplevel(true); f:SetMovable(true); f:EnableMouse(true)
  f:SetClampedToScreen(true); f:RegisterForDrag('LeftButton')
  f:SetScript('OnDragStart',function(w) self:StartMarketDrag(w) end)
  f:SetScript('OnDragStop',function(w) self:StopMarketDrag(w) end)
  f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=16,insets={left=4,right=4,top=4,bottom=4}})
  f:SetBackdropColor(0.025,0.022,0.04,0.97); f:SetBackdropBorderColor(0.45,0.3,0.7,1)
  if UIParent.GetWidth then f:SetScale(math.min(1,(UIParent:GetWidth()-30)/1040,(UIParent:GetHeight()-30)/680)) end
  self:RestoreWindowLayout()
  label(f,'VOIDMARK MARKET',18,-16,300,'GameFontNormalLarge')
  self.modeLabel=label(f,'Manual trading',365,-19,455)
  button(f,'TRANSFER',860,-12,125,function() self:ShowTransferWindow() end)
  button(f,'X',995,-12,26,function() self:CloseMarketWindow() end)
  self.navigation={}
  self.navOrder={}
  for i,v in ipairs(tabs) do local tab=v[2];self.navOrder[i]=tab;self.navigation[tab]=button(f,v[1],18+(i-1)*111,-48,107,function() self:SetView(tab) end) end
  self.dockBack=button(f,'< BACK',18,-48,120,function() local root=self:DockRootView();if root then self:SetView(root) end end)
  self.dockBack:Hide()
  self.syncFrame=CreateFrame('Frame',nil,f);self.syncFrame:SetPoint('TOPLEFT',18,-151);self.syncFrame:SetSize(1000,465)
  self.syncReport=label(self.syncFrame,'',0,-70,960)
  button(self.syncFrame,'RECONNECT',0,0,130,function() self:ReconnectSharing(false) end)
  button(self.syncFrame,'FORCE SYNC',140,0,130,function() self:ReconnectSharing(true) end)
  self.autoScanButton=button(self.syncFrame,'',280,0,220,function()
   if self.persistenceBlocked then return end
   self.db.settings.autoBankScan=self.db.settings.autoBankScan==false;self:RefreshUI()
  end)
  self:InitializeSimpleTradingUI(f,button,label)
  self.status=label(f,'',18,-84,700)
  self.connectionLabel=label(f,'',724,-84,290)
  self.toolbar=CreateFrame('Frame',nil,f); self.toolbar:SetPoint('TOPLEFT',18,-109); self.toolbar:SetSize(1000,34)
  self.scanButton=button(self.toolbar,'FULL SCAN',0,0,110,function() self:RequestFreshScan() end)
  self.cachedButton=button(self.toolbar,'CACHED',116,0,88,function() self:AnalyzeCachedSnapshot() end)
  self.filter=edit(self.toolbar,52,-1,252,self.db.settings.filter); self.filterLabel=label(self.toolbar,'Search:',0,-7,50)
  self.filter:SetScript('OnEnterPressed',function(e) e:ClearFocus();if self.view=='browse' then self:LiveNameSearch(e:GetText()) end end)
  self.searchButton=button(self.toolbar,'SEARCH',312,0,95,function() self:LiveNameSearch(self.filter:GetText()) end)
  self.filter:SetScript('OnTextChanged',function(e)
    self.db.settings.filter=e:GetText();self.shoppingSearchStatus=nil; self.page=1
    if self.view=='browse' then self:BuildBrowseRows(self.db.settings.filter) end
    self:RefreshUI()
  end)
  self.sortButton=button(self.toolbar,'SORT: SCORE',405,0,116,function()
    local sorts=self.view=='browse' and {'name','ask','profit','roi'} or {'score','profit','roi','confidence','liquidity','discount','ask','name'}; local current=self.db.settings.sort
    local known=false;for _,name in ipairs(sorts) do if name==current then known=true end end
    if not known then current=sorts[#sorts] end
    for i,v in ipairs(sorts) do if v==current then self.db.settings.sort=sorts[i%#sorts+1]; break end end
    if self.view=='browse' then self:SortBrowseRows() end
    self:RefreshUI()
  end)
  self.prevButton=button(self.toolbar,'<',525,0,32,function() self.page=math.max(1,(self.page or 1)-1); self:RefreshUI() end)
  self.nextButton=button(self.toolbar,'>',563,0,32,function() self.page=(self.page or 1)+1; self:RefreshUI() end)
  self.pageText=label(self.toolbar,'',604,-7,93)
  self.savedListButton=button(self.toolbar,'SAVED LISTS',702,0,130,function() self:SetView('shopping') end)
  self.tableFrame=CreateFrame('Frame',nil,f); self.tableFrame:SetPoint('TOPLEFT',18,-151); self.tableFrame:SetSize(1000,340)
  self.headings={}; self.rows={}
  local widths={250,105,105,110,95,90,110,135}; local x=0
  for i,w in ipairs(widths) do self.headings[i]=label(self.tableFrame,'',x,-2,w); x=x+w end
  for r=1,12 do
    local b=CreateFrame('Button',nil,self.tableFrame); self.rows[r]=b; b:SetPoint('TOPLEFT',0,-25-(r-1)*25); b:SetSize(1000,25)
    b:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight'); b.cols={}; local cx=0
    b.icon=b:CreateTexture(nil,'ARTWORK');b.icon:SetSize(20,20);b.icon:SetPoint('LEFT',2,0)
    b.selected=b:CreateTexture(nil,'BACKGROUND');b.selected:SetAllPoints();b.selected:SetColorTexture(0.32,0.15,0.5,0.45)
    b:SetScript('OnEnter',function(row) self:ShowRowTooltip(row) end)
    b:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
    for i,w in ipairs(widths) do b.cols[i]=label(b,'',cx+(i==1 and 26 or 0),-6,w-(i==1 and 31 or 5),'GameFontHighlight'); cx=cx+w end
    b:SetScript('OnClick',function(row)
      if not row.data then return end
      if self.view=='selling' then self:SelectSellRow(row.data,true);return end
      self.selectedRow=row.data
      if self.view=='vendor' then self.quantity:SetText(tostring(row.data.buyQuantity));self:SelectOpportunity(row.data)
      elseif self.view=='opportunities' then self:SelectOpportunity(row.data)
      elseif self.view=='review' and row.data.opportunity then self:SelectOpportunity(row.data.opportunity)
      elseif self.view=='my auctions' then self:AnalyzeOwnedLive(row.data)
      else self:RefreshUI() end
    end)
  end
  self.tableFrame:EnableMouseWheel(true)
  self.tableFrame:SetScript('OnMouseWheel',function(_,delta) self.page=math.max(1,(self.page or 1)-(delta>0 and 1 or -1));self:RefreshUI() end)
  self.historyAction=CreateFrame('Frame',nil,f);self.historyAction:SetPoint('BOTTOMLEFT',18,18);self.historyAction:SetSize(998,28)
  button(self.historyAction,'PRICE HISTORY',0,0,160,function() self:ShowHistoryWindow(self.selectedRow) end)
  button(self.historyAction,'GOLD HISTORY',170,0,160,function() self:ShowHistoryWindow(nil,true) end)
  self:InitializeSellScreen(f);self:InitializeShopScreen(f);self:InitializeCancelScreen(f);self:WarmItemNames()
  self.browseAction=CreateFrame('Frame',nil,f);self.browseAction:SetPoint('BOTTOMLEFT',18,18);self.browseAction:SetSize(998,28)
  button(self.browseAction,'BUY ITEM',0,0,180,function() self:ShopSelected(self.selectedRow) end)
  button(self.browseAction,'COMPARE LISTINGS',190,0,180,function() local ok,why=self:InspectLiveMarket(self.selectedRow);if not ok then self:Print(why or 'Select an item first') end end)
  button(self.browseAction,'ADD TO LIST',380,0,150,function()
   local row=self.selectedRow;if not row then self:Print('Select an item first');return end
   local ok,why=self:SetWatch(row.marketKey,nil);self:Print(ok and ('Added to '..self.activeList) or why)
  end)
  button(self.browseAction,'PRICE HISTORY',540,0,160,function() self:ShowHistoryWindow(self.selectedRow) end)
  self.presetButton=button(f,'PRESET: BALANCED',18,-628,210,function()
    local names={'balanced','conservative','exploratory'};local current=self.db.settings.sniperPreset or 'balanced'
    for i,name in ipairs(names) do if name==current then self:ApplySniperPreset(names[i%3+1]);break end end
  end)
  self.detail=label(f,'',18,-493,998,'GameFontHighlightSmall'); self.detail:SetHeight(125); self.detail:SetJustifyV('TOP')
  self.contentScroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate')
  self.contentScroll:SetPoint('TOPLEFT',18,-151); self.contentScroll:SetSize(976,465)
  local child=CreateFrame('Frame',nil,self.contentScroll); child:SetSize(972,460); self.contentScroll:SetScrollChild(child)
  self.content=label(child,'',0,0,960,'GameFontHighlight'); self.content:SetJustifyV('TOP')
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
    local ok,why=self:SetWatch(market and market.marketKey or (selected and (raw=='' or tostring(selected.itemID)==raw) and selected.marketKey) or id,copper)
    self:Print(ok and 'Watch target saved for this economy' or why)
  end)
  button(self.watchFrame,'REMOVE SELECTED',680,2,160,function()
    if not self.selectedRow or not self.selectedRow.marketKey then self:Print('Select a watched item first');return end
    self:RemoveWatch(self.selectedRow.marketKey);self.selectedRow=nil
  end)
  label(self.watchFrame,'List:',0,-44,40)
  self.listEdit=edit(self.watchFrame,42,-37,165,self.activeList)
  button(self.watchFrame,'OPEN / CREATE',217,-37,135,function()
   local ok,err=self:SetList(self.listEdit:GetText());if not ok then self:Print(err) end
  end)
  button(self.watchFrame,'NEXT LIST',360,-37,100,function()
   local names={'Shopping'};for name in pairs(self.db.shoppingLists) do names[#names+1]=name end
   table.sort(names);for i,n in ipairs(names) do if n==self.activeList then self:SetList(names[i%#names+1]);break end end
   self.listEdit:SetText(self.activeList)
  end)
  button(self.watchFrame,'BUY SELECTED',474,-37,145,function() self:ShopSelected(self.selectedRow) end)
  self.action=CreateFrame('Frame',nil,f); self.action:SetPoint('BOTTOMLEFT',18,18); self.action:SetSize(1000,28)
  self.quantity=edit(self.action,83,-1,80,'1'); label(self.action,'Quantity:',0,-7,80)
  self.revalidateButton=button(self.action,'CHECK PRICE',180,0,130,function() self:RevalidateSelected(self.quantity:GetText()) end)
  self.executeButton=button(self.action,'BUY',318,0,130,function() if self.execution.commodity then self:ExecuteClicked() else self:ReviewRegularPurchase() end end)
  self.confirmButton=button(self.action,'CONFIRM BUY',456,0,155,function() self:ConfirmClicked() end)
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
  button(self.sellAction,'QUEUE POST',763,0,116,function()
    local ok,why=self:QueuePostingReview(self.selectedRow)
    self:Print(ok and 'Saved posting intent; current bag and price will be checked again' or why)
  end)
  button(self.sellAction,'POST QUEUE',885,0,111,function()self:SetView('post review')end)
  self.ownedRefresh=button(f,'REFRESH MY AUCTIONS',18,-628,210,function() self:RequestOwnedAuctionsDiagnostic() end)
  self.cancelOwned=button(f,'CANCEL SELECTED...',238,-628,180,function() self:ReviewCancel(self.selectedRow) end)
  self.checkUndercuts=button(f,'CHECK UNDERCUTS',428,-628,170,function() self:CheckAllUndercuts() end)
  self.cancelNextUndercut=button(f,'CANCEL NEXT UNDERCUT...',608,-628,210,function() self:CancelNextUndercut() end)
  self.postReviewRemove=button(f,'REMOVE POST INTENT',18,-628,200,function()
    local row=self.selectedRow
    if row and row.marketKey then self:RemovePostingReview(row.marketKey);self.selectedRow=nil
    else self:Print('Select a posting queue entry first') end
  end)
  self.postReviewBack=button(f,'BACK TO SELL',226,-628,180,function() self:SetView('selling') end)
  self.reviewRemove=button(f,'REMOVE QUEUED ITEM',18,-628,200,function()
    if self.selectedRow and self.selectedRow.marketKey then
      if self:RemovePurchaseReview(self.selectedRow.marketKey) then self.selectedRow=nil end
    else self:Print('Select a queue entry first') end
  end)
  self.settingsFrame=CreateFrame('Frame',nil,f); self.settingsFrame:SetPoint('TOPLEFT',18,-151); self.settingsFrame:SetSize(998,460)
  button(self.settingsFrame,'SCALE -',0,-425,100,function() self:ChangeWindowScale(-0.05) end)
  button(self.settingsFrame,'SCALE +',108,-425,100,function() self:ChangeWindowScale(0.05) end)
  button(self.settingsFrame,'RESET WINDOW',216,-425,150,function()
    if self.auctionDock then self:ResetAuctionLayout();return end
    self.db.settings.window=nil;self.window:ClearAllPoints();self.window:SetPoint('CENTER');self:ChangeWindowScale(0,true)
  end)
  local settings={
    {'maxTransaction','Maximum transaction (gold)',10000},{'maxItemSpend','Maximum per-item exposure (gold)',10000},
    {'maxExposure','Maximum portfolio exposure (gold)',10000},{'maxQuantity','Maximum quantity',1},
    {'minProfit','Minimum expected profit (silver)',100},{'minROI','Minimum ROI (%)',0.01},
    {'minConfidence','Minimum confidence (0-100)',1},{'minLiquidity','Minimum inferred liquidity (0-100)',1},
    {'riskTolerance','Maximum volatility (%)',0.01},{'depositReserve','Resale deposit allowance/unit (silver)',100},
    {'ahCut','AH cut (%) - verify current AH',0.01},{'maxDataAge','Maximum model age (minutes)',60},
    {'minGoldReserve','Minimum liquid gold reserve (gold)',10000},
    {'sellMinMargin','Known-cost minimum margin (%)',0.01},{'sellUndercut','Selling undercut (copper)',1}}
  self.settingFields={}
  for i,s in ipairs(settings) do
    local col=(i-1)%2; local row=math.floor((i-1)/2); local x=col*495
    label(self.settingsFrame,s[2],x,-row*44,355)
    local e=edit(self.settingsFrame,x+365,-row*44+3,100,tostring(self.db.settings[s[1]]/s[3]))
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
    values.maxQuantity=math.floor(values.maxQuantity);values.sellUndercut=math.floor(values.sellUndercut)
    for k,v in pairs(values) do self.db.settings[k]=v end
    if self.execution.state=='quoted' then self:InvalidateQuote('Limits changed; revalidate')
    elseif self.execution.state=='ready' then self.execution.state='stale'; self.execution.message='Limits changed; revalidate' end
    self:RebuildOpportunities(); self:RefreshUI()
  end)
  label(self.settingsFrame,'Partner (First Surname):',175,-354,190)
  self.partner=edit(self.settingsFrame,374,-348,190,self.db.syncAddress or self.db.syncPeer or '')
  button(self.settingsFrame,'PAIR',575,-348,75,function() self:Print(self:PairPeer(self.partner:GetText())) end)
  button(self.settingsFrame,'UNPAIR',658,-348,85,function() self:Print(self:PairPeer('off'));self.partner:SetText('') end)
  self.syncState=label(self.settingsFrame,'',180,-394,775)
  self.minimapToggle=CreateFrame('CheckButton',nil,self.settingsFrame,'UICheckButtonTemplate')
  self.minimapToggle:SetPoint('TOPLEFT',0,-386); self.minimapToggle:SetSize(28,28)
  label(self.settingsFrame,'Show minimap icon',34,-394,240)
  self.minimapToggle:SetChecked(not (self.root.settings.minimap and self.root.settings.minimap.hide))
  self.minimapToggle:SetScript('OnClick',function(c)
    self:SetMinimapIconVisible(c:GetChecked() and true or false)
  end)
  label(self.settingsFrame,'Paired characters sync while both are online.\nTransfer also works offline by copying text.',385,-424,590)
  self.view='browse';self:BuildBrowseRows(self.db.settings.filter or ''); self.page=1; self:RefreshUI(); f:Hide() -- Keep Market closed on login/reload until opened by the user.
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
  if self.craftAction then self.craftAction:Hide() end
  local view=self.view or 'market'; local s=self.db.settings
  self.modeLabel:SetText(self.persistenceBlocked and '|cffff9966Read-only: newer database|r' or 'Search. Compare. Buy and sell.')
  self.status:SetText(self:SimpleScanStatus())
  self.connectionLabel:SetText(self:SimpleSyncStatus())
  self.historyAction:SetShown(view=='investments' or view=='banker' or view=='market')
  self.cancelOwned:SetShown(view=='my auctions');self.checkUndercuts:SetShown(view=='my auctions');self.cancelNextUndercut:SetShown(view=='my auctions');self.browseAction:Hide();self.presetButton:SetShown(view=='opportunities')
  self.presetButton:SetText('PRESET: '..(s.sniperPreset or 'balanced'):upper())
  self.toolbar:Show(); self.tableFrame:Hide(); self.detail:Hide(); self.contentScroll:Hide(); self.settingsFrame:Hide(); self.action:Hide(); self.ledgerAction:Hide(); self.ownedRefresh:Hide(); self.reviewRemove:Hide(); self.postReviewRemove:Hide(); self.postReviewBack:Hide(); self.sellAction:Hide(); self.watchFrame:Hide(); self.statsFrame:Hide()
  self.filter:SetShown(view=='vendor' or view=='opportunities' or view=='browse' or view=='crafting' or view=='shopping'); self.sortButton:SetShown(view=='opportunities' or view=='browse' or view=='crafting'); self.sortButton:SetText('SORT: '..s.sort:upper())
  if view=='browse' then
    local names={profit='SPREAD',roi='FAIR/ASK',ask='ASK',name='NAME'}
    self.sortButton:SetText('SORT: '..(names[s.sort] or 'NAME'))
  end
  self.detail:SetHeight(view=='selling' and 90 or 125)
  self.scanButton:SetEnabled(self.ahOpen and not self.scanState.running and self:GetSecondsUntilFreshScanAllowed()==0); self.cachedButton:SetEnabled(self.ahOpen and not self.scanState.running)
  self:RenderSimpleTradingUI(view)
  self.syncFrame:Hide()
  self.sellScreen:Hide();self.shopScreen:Hide();self.cancelScreen:Hide()
  if view=='selling' or view=='browse' or view=='my auctions' then
   self.toolbar:Hide();self.shoppingSidebar:Hide();self.browseAction:Hide();self.emptyMessage:Hide()
   self.tableFrame:Hide();self.detail:Hide()
   for _,b in ipairs({self.ownedRefresh,self.cancelOwned,self.checkUndercuts,self.cancelNextUndercut}) do b:Hide() end
   if view=='selling' then return self:RenderSellScreen() end
   if view=='my auctions' then return self:RenderCancelScreen() end
   return self:RenderShopScreen()
  end
  if view=='crafting' or view=='materials' or view=='goldmaking' then return self:RenderCraftingUI(view) end
  if view=='sync' then
   self.toolbar:Hide();self.syncFrame:Show();self.syncReport:SetText(self:SyncReport())
   self.autoScanButton:SetText('AUTO BANK SCAN: '..(s.autoBankScan==false and 'OFF' or 'ON'));return
  end
  if view=='tools' then return end
  if view=='settings' then self.settingsFrame:Show(); self.syncState:SetText(self:SharingStatus()); self.minimapToggle:SetChecked(not (s.minimap and s.minimap.hide)); return end
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
    local lines={'|cffffffffBUY ITEM|r',m and m.name or 'Select an item in Shopping or Vendor Deals.','',x.message}
    if x.live then
      local live=x.live;local e=live.economics
      lines[#lines+1]=''
      lines[#lines+1]='Quantity: '..live.quantity
      lines[#lines+1]='Price per item: '..self:Money(live.cost/math.max(1,live.quantity))
      lines[#lines+1]='Total cost: '..self:Money(live.cost)
      if e and e.kind=='vendor' then
        lines[#lines+1]='Vendor return: '..self:Money(e.gross)
        lines[#lines+1]='Vendor profit: '..self:Money(e.net)
      end
      lines[#lines+1]=''
      lines[#lines+1]=x.commodity and 'GET QUOTE checks the total. CONFIRM BUY purchases at the accepted price.' or 'BUY purchases one complete auction after confirmation.'
    else
      lines[#lines+1]=''
      lines[#lines+1]='Choose how many items you want below, then click CHECK PRICE.'
    end
    self.executeButton:SetText(x.commodity and 'GET QUOTE' or 'BUY')
    self.confirmButton:SetShown(x.state=='quoted')
    self.cancelQuoteButton:SetShown(x.state=='quoted' or x.state=='quoting')
    self.addReviewButton:SetShown(x.opportunity and x.opportunity.kind~='shopping' or false)
    self.revalidateButton:SetEnabled(not self.persistenceBlocked and self.ahOpen and m~=nil and not self:HasUnresolvedPurchase() and x.state~='quoting' and x.state~='quoted' and x.state~='validating')
    self.executeButton:SetEnabled(not self.persistenceBlocked and self.ahOpen and x.state=='ready' and not self:HasUnresolvedPurchase())
    self.confirmButton:SetEnabled(not self.persistenceBlocked and self.ahOpen and x.state=='quoted')
    self.cancelQuoteButton:SetEnabled(x.state=='quoted' or x.state=='quoting')
    self.addReviewButton:SetEnabled(x.opportunity~=nil and x.opportunity.kind~='shopping' and not self.persistenceBlocked)
    text=table.concat(lines,'\n')
  elseif view=='diagnostics' then text=self:BuildTextReport()
  elseif view=='market' then
    local scan=self.db.latestScan; local stats=self.db.marketStats or {}; local totals=self:LedgerTotals()
    text='|cffffffffLOCAL MARKET TERMINAL|r\n\n'..#(self.marketIndex or {})..' markets | '..#self.db.opportunities..' ranked candidates\nEconomy: '..self.economyID..'\n\n'
    if scan then text=text..string.format('Last scan %s\nRows %d | valid %d | invalid %d | incomplete %d\nMarkets %d | total supply %d | elapsed %s ms | generation #%s\n\n',date('%Y-%m-%d %H:%M',scan.completedAt or time()),scan.rawRows or 0,scan.auctionsProcessed or 0,scan.invalidRecords or 0,scan.incompleteRecords or 0,scan.uniqueItems or 0,scan.totalQuantity or 0,tostring(scan.processingMS),tostring(scan.marketScanID)) end
    if scan and scan.deferredRows then text=text..string.format('Item data: %d deferred | %d recovered | %d unresolved\n\n',scan.deferredRows,scan.recoveredRows or 0,scan.unresolvedRows or 0) end
    text=text..self:FinancialSummaryText()..'\n\n'
    text=text..'Cost-matched realized '..self:Money(totals.realized)..' | verified net sale revenue '..self:Money(totals.revenue)..'\n'..
      'Portfolio liquidation uses fresh models with sufficient history/confidence. Unproven positions remain unpriced.\n'..
      'Scan results are advisory. SHOPPING checks live prices before buying; SELLING reviews and posts bag items.\n'..
      'HISTORY shows scan changes and watch alerts. /vmm report opens diagnostics.'
  elseif view=='banker' then
    local summary=self:GetBankerSummary()
    local banker=summary.scanner or {}
    local scan=summary.latestScan
    local lines={'|cffffffffPRICE HISTORY|r','',
      'Liquid reserve '..self:Money(summary.reserve)..' | Available after reserve/pending '..self:Money(summary.available),
      'Portfolio positions '..summary.portfolio.positions..' | Unpriced cost '..self:Money(summary.portfolio.unvaluedCost),
      'Estimated unrealized net '..self:Money(summary.portfolio.unrealized)..' (fresh models only)',
      'Confirmed realized result '..self:Money(summary.realized)..' | Unresolved spend '..self:Money(summary.pending),'',
      'Latest published snapshot: '..(scan and date('%Y-%m-%d %H:%M',scan.completedAt or time()) or 'none'),
      'New passing opportunities since previous FRESH completed scan: '..#(banker.new or {})}
    for i,o in ipairs(banker.new or {}) do
      if i>12 then lines[#lines+1]='...more candidates in Tools > Flip opportunities';break end
      lines[#lines+1]=tostring(o.name)..' | rank '..tostring(o.score)
    end
    lines[#lines+1]=''
    lines[#lines+1]='WATCH MOVEMENTS (10% change or target crossing)'
    for i,a in ipairs(banker.movements or {}) do
      if i>8 then break end
      lines[#lines+1]=tostring(a.name)..' | '..self:PercentText(a.change)..' | '..self:Money(a.price)..(a.target and ' TARGET CROSSED' or '')
    end
    lines[#lines+1]='Cached analyses do not create independent history or new opportunity alerts.'
    lines[#lines+1]='No unattended transactions. Open the AH and click SCAN AUCTION HOUSE when the cooldown permits.'
    text=table.concat(lines,'\n')
  else
    local source,headers={},{'Name','Ask','Fair','Net','ROI','Score','Confidence','Liquidity'}
    if view=='vendor' then
      source=self:GetVendorRows(s.filter);headers={'Below vendor','AH/unit','Vendor/unit','Profit/unit','Units','Buy all','Profit all','State'}
    elseif view=='opportunities' then
      source=self:GetSniperRows(s.filter,s.sort)
      headers={'Item / status','Ask','Model est.','Net est.','ROI','Score','Confidence','Risk'}
    elseif view=='review' then
      source=self:GetPurchaseReviewRows();self.reviewRemove:Show()
      headers={'Saved candidate','Old ask','Latest ask','Fair','ROI','','Confidence','State'}
    elseif view=='browse' then
      self.browseAction:Show();source=self:ShoppingResultRows(); headers={'Item','Lowest / unit','Available','Price age','Source','','',''}
    elseif view=='shopping' then
      source={};local needle=(s.filter or ''):lower()
      for _,row in ipairs(self:GetWatchRows()) do if needle=='' or row.name:lower():find(needle,1,true) or tostring(row.itemID)==needle then source[#source+1]=row end end
      headers={'Watched item','Item ID','Ask/unit','Fair','Target','','Confidence','State'}
      self.watchFrame:Show()
    elseif view=='investments' then
      source=self:GetPortfolioRows();headers={'Owned investment','Quantity','Cost basis','Net est.','Unrealized','ROI','Age','State'}
    elseif view=='selling' then source=self.sellingRows; self.sellAction:Show();self.sellStrategyButton:SetText('MODE: '..(s.sellStrategy or 'competitive'):upper()); headers={'Inventory','Quantity','Suggest/unit','Model est.','Basis/unit','Net est.','Confidence','State'}
    elseif view=='post review' then
      source=self:GetPostingReviewRows();self.postReviewRemove:Show();self.postReviewBack:Show()
      headers={'Posting intent','In bag','Old quote','Current quote','Fair','','','State'}
    elseif view=='my auctions' then source=self.ownedRows; self.ownedRefresh:Show(); headers={'My listing','Quantity','My unit','Lowest other','Time left','State','',''}
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
    if view=='selling' and self.selectedRow then
      local selected=self.selectedRow;self.selectedRow=nil
      for _,current in ipairs(source) do
        if current.bag==selected.bag and current.slot==selected.slot and current.marketKey==selected.marketKey then
          self.selectedRow=current;break
        end
      end
    end
    self.pageText:SetText(self.page..' / '..pages..' ('..#source..')')
    self:ShowTradingEmptyState(view,#source)
    self.tableFrame:Show(); self.detail:Show()
    for i,h in ipairs(headers) do self.headings[i]:SetText(h) end
    for i,row in ipairs(self.rows) do
      local o=source[(self.page-1)*12+i]; row.data=o; row:SetShown(o~=nil)
      if o then
        row.selected:SetShown(self.selectedRow==o)
        local id=o.itemID or (o.marketKey and self.db.market[o.marketKey] and self.db.market[o.marketKey].itemID)
        local icon=self:RowItemIcon(o,id)
        row.icon:SetTexture(icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
        local cells
        if view=='vendor' then cells={o.name,self:Money(o.floor),self:Money(o.vendorPrice),self:Money(o.vendorPrice-o.floor),o.quantity,self:Money(o.totalCost),self:Money(o.totalProfit),o.status}
        elseif view=='opportunities' then cells={(o.pass and '' or '|cffff9a9a[BLOCKED]|r ')..(o.kind=='vendor' and '|cff72e7aa[VENDOR]|r ' or '')..o.name,
          self:Money(o.floor),(o.kind=='vendor' or self:CanEstimateResale(self.db.market[o.marketKey])) and self:Money(o.fairValue) or 'Unproven',
          (o.kind=='vendor' or self:CanEstimateResale(self.db.market[o.marketKey])) and self:Money(o.economics.net) or '--',
          (o.kind=='vendor' or self:CanEstimateResale(self.db.market[o.marketKey])) and self:PercentText(o.economics.roi) or '--',
          o.score,o.confidence,o.risk}
        elseif view=='review' then cells={o.name,self:Money(o.snapshotAsk),o.ask>0 and self:Money(o.ask) or 'Missing',
          self:Money(o.fair),self:PercentText(o.roi),'',o.confidence,o.status}
        elseif view=='browse' then cells={o.name,o.floor>0 and self:Money(o.floor) or (o.status=='NONE' and 'None listed' or 'Unknown'),o.quantity or '--',o.status=='LIVE BROWSE' and 'Just now' or self:PriceAge(o.at),(o.status=='LIVE BROWSE' or o.status=='LIVE' or o.status=='NONE') and 'Live search' or o.status=='SYNCED' and 'Bank scan' or o.status=='SYNC STALE' and 'Bank scan (old)' or o.status=='STALE' and 'Old scan' or 'Local scan','','',''}
        elseif view=='shopping' then cells={o.name,o.itemID,self:Money(o.floor),self:Money(o.fair),o.target and self:Money(o.target) or 'Any','',o.confidence,o.status}
        elseif view=='investments' then cells={o.name,o.quantity,self:Money(o.cost),o.estimatedNet and self:Money(o.estimatedNet) or 'Unknown',
          o.unrealized and self:Money(o.unrealized) or 'Unknown',o.roi and self:PercentText(o.roi) or 'N/A',o.ageDays and (o.ageDays..'d') or 'Unknown age',o.status}
        elseif view=='selling' then cells={o.name,o.quantity,o.price and self:Money(o.price) or 'No quote',o.fair and self:Money(o.fair) or '--',o.basisUnit and self:Money(o.basisUnit) or 'Unknown',o.estimatedNet and self:Money(o.estimatedNet) or '--',o.confidence,o.status}
        elseif view=='post review' then cells={o.name,o.quantity,o.snapshotUnit and self:Money(o.snapshotUnit) or '--',
          o.price and self:Money(o.price) or '--',o.fair and self:Money(o.fair) or '--','','',o.status}
        elseif view=='my auctions' then cells={o.name,o.quantity,self:Money(o.unit),o.competition and self:Money(o.competition) or (o.liveAt and 'None' or '?'),
          self:FormatTimeLeft(o.timeLeft),self:OwnedState(o),'',''}
        else cells={(o.kind or '')..': '..tostring(o.name or o.auctionID or ''),o.quantity or '',o.cost and self:Money(o.cost) or '',o.gross and self:Money(o.gross) or '',o.booked and 'booked' or o.status,o.id,o.evidence or '',''} end
        for j=1,8 do row.cols[j]:SetText(tostring(cells[j] or '')) end
      end
    end
    local o=self.selectedRow
    if view=='vendor' then self.detail:SetText('Click SCAN AUCTION HOUSE to find auctions below their vendor sell value. Sorted by total vendor profit; includes small deals regardless of sniper filters.\nUnits and totals include only profitable whole stacks, excluding your own listings. Partial depth totals are a lower bound.\nClick an item, then CHECK PRICE to see current listings before buying. Purchase limits still apply.\nNo results? Run a fresh scan; items without a known vendor value are omitted.')
    elseif view=='opportunities' then self.detail:SetText('Select a row to inspect economics and revalidate live prices. Vendor opportunities have a separate model.\nResale rankings weigh absolute profit, ROI, confidence, inferred liquidity, depth, volatility and capital exposure.\nA snapshot opportunity may fail current limits or disappear before you buy. Live prices expire after 10 seconds.')
    elseif view=='review' then
      self.detail:SetText('This is an advisory purchase REVIEW QUEUE, not a transaction queue.\nItems marked REVALIDATE can be clicked to inspect, but the live purchase still needs complete search validation and a permitted user click.\nRECHECK items have stale/blocked/missing market data. They remain saved until you remove them.')
    elseif view=='shopping' then
      self.detail:SetText('List: '..self.activeList..' | Select an item to update or remove its target. Enter a base item ID and target in gold below.\nTargets only flag fresh cached asking prices; no automatic purchases.')
    elseif view=='investments' then
      local _,p=self:GetPortfolioRows()
      self.detail:SetText('Capital at known cost '..self:Money(p.cost)..' | modeled liquidation after estimated fees '..self:Money(p.estimatedNet)..
        '\nEstimated unrealized '..self:Money(p.unrealized)..' | not currently priceable '..self:Money(p.unvaluedCost)..
        '\nOnly known-cost purchases with sufficient pricing evidence are valued. Estimates are not confirmed sales.')
    elseif view=='post review' then
      self.detail:SetText(o and ('Posting intent only for '..tostring(o.name)..' | '..tostring(o.status)..
        '\n'..tostring(o.reason or '')..
        '\nNo bag slot is persisted; current stock and live posting prices must be checked again in the native Auction House.') or
        'Choose an entry. Queue items are bookmarks only and cannot post themselves.')
    elseif view=='selling' then
      if o and o.bag~=nil then
        self.detail:SetText('Bag '..o.bag..' / slot '..o.slot..' | '..tostring(o.status)..' | '..tostring(o.strategy or 'No strategy')..
          '\n'..(o.price and ('Price per unit '..self:Money(o.price)..' | Gross '..self:Money(o.gross)..' | estimated AH cut '..self:Money(o.estimatedCut)..' | deposit allowance '..self:Money(o.depositAllowance)) or 'No reliable pricing available')..
          '\n'..(o.profit and ('Estimated net profit '..self:Money(o.profit)..' | ROI '..self:PercentText(o.roi or 0)) or 'Profit unavailable: basis is not fully known')..
          '\n'..tostring(o.reason or '')..'\n'..self:StackPlanText(o)..'\n'..(self.postQuote and self.postQuote.at and ('Live lowest: '..(self.postQuote.floor and self:Money(self.postQuote.floor) or 'none')..(self.postQuote.atMinimum and ' | price held at your minimum' or ' | price = lowest minus '..self:Money(self.db.settings.sellUndercut or 1))) or (self.postQuote and 'Checking live price...' or 'Click an item to check its live price, then POST.')))
      else self.detail:SetText('Select a bag item for its price, cost basis and risk. Choose Check Price to compare live listings.') end
    elseif view=='my auctions' then
      local u,l,n=self:UndercutSummary()
      local summary=u..' undercut | '..l..' lowest | '..n..' not checked. CHECK UNDERCUTS searches each item; CANCEL NEXT UNDERCUT asks before each cancel.'
      self.detail:SetText(summary..'\n'..(o and ('Own auction #'..tostring(o.auctionID)..' | '..tostring(o.action or 'INSPECT')..
        '\n'..tostring(o.reason or 'Select a row to fetch live competition.')..
        '\n'..(o.repriceDifference and ('Gross reduction on reprice '..self:Money(o.repriceDifference)) or 'No repricing economics available')..
        '\nCancel Selected shows the current fee before you confirm.') or
        'Select an auction to inspect the live competitors. No cancel/post action is automatic.'))
    elseif view=='browse' then
      self.detail:SetText(o and (o.name..'\n'..self:LiveMarketText(o.marketKey)..'\nChoose BUY ITEM to check the current price and quantity.') or 'Type an item name and press Enter or SEARCH. Full scans and bank prices are also searchable here.\nSelect an item to compare its current listings or buy it.')
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
    label(f,'TWO-ACCOUNT MARKET + SHOPPING TRANSFER',18,-14,600,'GameFontNormalLarge')
    button(f,'CLOSE',746,-11,87,function()f:Hide()end)
    label(f,'Export prices or shopping targets; copy text on one account, paste into the other.',18,-48,810)
    label(f,'Matching realm/faction required. Shopping imports add missing entries; existing targets stay unchanged. No automatic trades.',18,-70,810)
    local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',18,-108);scroll:SetSize(794,395)
    local e=CreateFrame('EditBox',nil,scroll);e:SetMultiLine(true);e:SetFontObject('ChatFontNormal')
    e:SetWidth(768);e:SetAutoFocus(false);e:SetScript('OnEscapePressed',function()f:Hide()end)
    scroll:SetScrollChild(e);self.transferEdit=e
    self.transferStatus=label(f,'No data transferred',18,-521,810)
    local pricePage,pricePages=0,1
    local function prices(page)
      local raw,err,current,total=self:ExportMarketTransfer(page)
      if not raw then self.transferStatus:SetText(err);return end
      pricePage,pricePages=current,total;e:SetText(raw);e:SetFocus();e:HighlightText()
      self.transferStatus:SetText('Prices '..current..' / '..total..' | Copy and import each page.')
    end
    button(f,'EXPORT PRICES',18,-537,180,function() prices(1) end)
    button(f,'IMPORT PASTED TEXT',211,-537,195,function()
      local ok,msg=self:ImportMarketTransfer(e:GetText())
      self.transferStatus:SetText((ok and '|cff72e7aa' or '|cffff7777')..tostring(msg)..'|r')
    end)
    button(f,'NEXT PRICES',419,-537,125,function() prices(pricePage%pricePages+1) end)
    button(f,'EXPORT SHOPPING',550,-537,139,function()
      local raw,err=self:ExportShoppingTransfer()
      if raw then e:SetText(raw);e:SetFocus();e:HighlightText();self.transferStatus:SetText('Shopping list ready; Ctrl+C to copy')
      else self.transferStatus:SetText(err or 'Shopping export failed') end
    end)
    button(f,'IMPORT SHOPPING',699,-537,134,function()
      local ok,msg=self:ImportShoppingTransfer(e:GetText())
      self.transferStatus:SetText((ok and '|cff72e7aa' or '|cffff7777')..tostring(msg)..'|r')
    end)
  end
  self.transferWindow:Show()
end

