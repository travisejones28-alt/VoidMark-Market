local _,M=...
function M:PriceAge(at)
 if not self:Finite(at,1,time()+60) then return 'Unknown' end
 local age=math.max(0,time()-at)
 if age<60 then return 'Just now' end
 if age<3600 then return math.floor(age/60)..' min ago' end
 if age<86400 then return math.floor(age/3600)..' hr ago' end
 return math.floor(age/86400)..' days ago'
end
function M:SimpleScanStatus()
 local list=self.ListSearchStatus and self:ListSearchStatus();if list then return list end
 local s=self.scanState;local cooldown=self:GetSecondsUntilFreshScanAllowed()
 local retry=cooldown>0 and (' | Next scan in '..self:FormatDuration(cooldown)) or ''
 if s.running then
  if s.phase=='processing' then return 'Scanning auctions: '..tostring(s.processed or 0)..' / '..tostring(s.snapshotRows or 0)..' | Keep the AH open' end
  if s.phase=='model' then return 'Calculating prices and vendor deals | Keep the AH open' end
  if s.phase=='hydrating' then return 'Loading item details | Keep the AH open' end
  return 'Waiting for the Auction House to send prices | Keep the AH open'
 end
 if s.phase=='error' then return '|cffff9999Scan failed: no completed scan. See Tools > Diagnostics.|r'..retry end
 if s.phase=='aborted' then return 'Scan stopped when the Auction House closed'..retry end
 local scan=self.db.latestScan
 if scan then return 'Last scan: '..self:PriceAge(scan.completedAt)..' | '..tostring(scan.auctionsProcessed or 0)..' auctions'..retry end
 return (self.ahOpen and 'Ready to scan' or 'Open the Auction House to search or scan')..retry
end
function M:SimpleSyncStatus()
 if not self.db.syncPeer then return 'Bank sync: not paired' end
 local r=self.shareRun or {};local rx=self.db.shareReceived[self.db.syncPeer] or {}
 if not r.lastContact or GetTime()-r.lastContact>65 then return 'Bank sync: waiting for partner' end
 if rx.total and rx.seq<rx.total then return 'Bank sync: receiving '..math.floor(rx.seq/rx.total*100)..'%' end
 local j=self.db.shareJournal
 if r.cursor and r.cursor<j.seq then return 'Bank sync: sending '..math.floor(r.cursor/math.max(1,j.seq)*100)..'%' end
 return 'Bank sync: connected'
end
function M:InitializeSimpleTradingUI(f,button,label)
 self.toolsFrame=CreateFrame('Frame',nil,f);self.toolsFrame:SetPoint('TOPLEFT',18,-151);self.toolsFrame:SetSize(998,465)
 label(self.toolsFrame,'MARKET TOOLS',0,0,800,'GameFontNormalLarge')
 local tools={{'Scan overview','market','Scan totals and your gold'}, {'Bank sync','sync','Connection, transfer progress and pairing'},
  {'Saved shopping lists','shopping','Manage lists and target prices'}, {'Flip opportunities','opportunities','Resale candidates and filters'},
  {'Purchase queue','review','Items saved for later'}, {'Price history','banker','Scan changes and watch alerts'},
  {'Investments','investments','Tracked purchases and cost'}, {'Ledger','ledger','Recorded buys and sales'},
  {'Settings','settings','Trading limits and display'}, {'Diagnostics','diagnostics','Detailed error and scan reports'}}
 for i,t in ipairs(tools) do
  local x=(i-1)%2*500;local y=-40-math.floor((i-1)/2)*76;local view=t[2]
  button(self.toolsFrame,t[1],x,y,220,function() self:SetView(view) end)
  label(self.toolsFrame,t[3],x,y-32,465,'GameFontHighlight')
 end
 self.emptyMessage=label(f,'',45,-275,940,'GameFontHighlightLarge');self.emptyMessage:SetJustifyH('CENTER')
 self.shoppingSidebar=CreateFrame('Frame',nil,f,'BackdropTemplate');self.shoppingSidebar:SetPoint('TOPLEFT',18,-151);self.shoppingSidebar:SetSize(194,460)
 self.shoppingSidebar:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});self.shoppingSidebar:SetBackdropColor(.055,.045,.075,.95)
 label(self.shoppingSidebar,'SHOPPING LISTS',10,-12,175)
 button(self.shoppingSidebar,'Search all items',8,-40,178,function()
  self.shoppingListMode=false;self:BuildBrowseRows(self.db.settings.filter or '');self:RefreshUI()
 end)
 self.listButtons={}
 for i=1,10 do
  local b=button(self.shoppingSidebar,'',8,-75-(i-1)*29,178,function(b)
   if b.listName then
    self:SetList(b.listName);self.shoppingListMode=true
    if self.ahOpen then self:SearchShoppingList() end -- like Auctionator: opening a list searches it
    self:RefreshUI()
   end
  end);self.listButtons[i]=b
 end
 self.searchListButton=button(self.shoppingSidebar,'Search this list',8,-370,178,function()
  if not self.shoppingListMode then self:Print('Choose a shopping list first');return end
  self:SearchShoppingList()
 end)
 button(self.shoppingSidebar,'Manage lists',8,-405,178,function() self:SetView('shopping') end)
 -- Clear, task-specific purchase controls under the shopping results.

end
function M:RenderSimpleTradingUI(view)
 self.toolsFrame:SetShown(view=='tools');self.emptyMessage:Hide()
 self:LayoutNavigation(view)
 self.shoppingSidebar:SetShown(view=='browse')
 if view=='browse' then
  local names={'Shopping'};for name in pairs(self.db.shoppingLists) do names[#names+1]=name end;table.sort(names)
  self.searchListButton:SetEnabled(self.shoppingListMode and self.ahOpen and true or false)
  for i,b in ipairs(self.listButtons) do b.listName=names[i];b:SetShown(names[i]~=nil);if names[i] then b:SetText((self.shoppingListMode and self.activeList==names[i] and '> ' or '')..names[i]) end end
 end
 local paged=view=='browse' or view=='vendor' or view=='shopping' or view=='opportunities' or view=='selling' or view=='my auctions' or view=='ledger' or view=='review' or view=='post review' or view=='investments' or view=='crafting'
 self.prevButton:SetShown(paged);self.nextButton:SetShown(paged);self.pageText:SetShown(paged)
 self.searchButton:SetShown(view=='browse');self.savedListButton:SetShown(view=='shopping')
 local searchable=view=='browse' or view=='vendor' or view=='opportunities' or view=='crafting' or view=='shopping'
 self.filterLabel:SetShown(searchable)
 self.scanButton:ClearAllPoints();self.scanButton:SetPoint('TOPLEFT',835,0);self.scanButton:SetWidth(160);self.scanButton:SetText('SCAN AUCTION HOUSE')
 self.scanButton:SetShown(view=='browse' or view=='vendor' or view=='market' or view=='banker' or view=='diagnostics')
 self.cachedButton:ClearAllPoints();self.cachedButton:SetPoint('TOPLEFT',702,0);self.cachedButton:SetWidth(125);self.cachedButton:SetText('READ AH CACHE');self.cachedButton:SetShown(view=='diagnostics')
 self.sortButton:SetShown(view=='opportunities' or view=='crafting')
 self.sortButton:ClearAllPoints();self.sortButton:SetPoint('TOPLEFT',312,0)
 if view=='browse' then
  self.tableFrame:ClearAllPoints();self.tableFrame:SetPoint('TOPLEFT',230,-151);self.tableFrame:SetWidth(788)
  self.detail:ClearAllPoints();self.detail:SetPoint('TOPLEFT',230,-493);self.detail:SetWidth(788)
  self.browseAction:ClearAllPoints();self.browseAction:SetPoint('BOTTOMLEFT',230,18)
 else
  self.tableFrame:ClearAllPoints();self.tableFrame:SetPoint('TOPLEFT',18,-151);self.tableFrame:SetWidth(1000)
  self.detail:ClearAllPoints();self.detail:SetPoint('TOPLEFT',18,-493);self.detail:SetWidth(998)
 end
 self:SetTradingColumns(view)
 if view=='tools' or view=='settings' or view=='execution' then self.toolbar:Hide() end
end
-- Docked from Shopping/Selling/Cancelling the screen stands alone like an
-- Auctionator tab (only a BACK button for sub-screens). The VoidMark tab shows
-- the remaining sections. The standalone /vmm window shows everything.
local tradingViews={browse=true,selling=true,['my auctions']=true}
function M:LayoutNavigation(view)
 local section=self.auctionDock and self.dockSection
 local x=0
 for _,target in ipairs(self.navOrder or {}) do
  local b=self.navigation[target]
  local shown=not section or (section=='voidmark' and not tradingViews[target])
  b:SetShown(shown);b:SetEnabled(target~=view)
  if shown then b:ClearAllPoints();b:SetPoint('TOPLEFT',18+x*111,-48);x=x+1 end
 end
 local root=section and section~='voidmark' and self:DockRootView()
 if self.dockBack then self.dockBack:SetShown(root and view~=root or false) end
end
function M:SetTradingColumns(view)
 local widths=view=='browse' and {285,140,95,125,143,0,0,0} or {250,105,105,110,95,90,110,135}
 local x=0
 for i,w in ipairs(widths) do
  local heading=self.headings[i];heading:ClearAllPoints();heading:SetPoint('TOPLEFT',x,-2);heading:SetWidth(math.max(1,w));heading:SetShown(w>0)
  for _,row in ipairs(self.rows) do
   row:SetWidth(view=='browse' and 788 or 1000)
   local col=row.cols[i];col:ClearAllPoints();col:SetPoint('TOPLEFT',x+(i==1 and 26 or 0),-6)
   col:SetWidth(math.max(1,w-(i==1 and 31 or 5)));col:SetShown(w>0)
  end
  x=x+w
 end
end
function M:ShoppingResultRows()
 if not self.shoppingListMode then return self.browseRows or {} end
 local out={};local needle=(self.db.settings.filter or ''):lower()
 for _,row in ipairs(self:GetWatchRows()) do
  if needle=='' or row.name:lower():find(needle,1,true) or tostring(row.itemID)==needle then
   local p=self:PriceObservation(row.marketKey);row.at=p and p.at;row.quantity=p and p.quantity
   local fresh=p and not p.unverified and time()-p.at<=self.db.settings.maxDataAge
   row.status=p and (p.source=='Live search' and (fresh and 'LIVE' or 'STALE') or p.source=='Synced account' and (fresh and 'SYNCED' or 'SYNC STALE') or (fresh and 'CACHED' or 'STALE')) or 'Unknown'
   local none=self.listEmpty and self.listEmpty[row.marketKey]
   if none and (not p or none>=p.at) then row.status='NONE';row.floor=0;row.quantity=0;row.at=none end
   out[#out+1]=row
  end
 end
 return out
end
function M:ShowTradingEmptyState(view,n)
 if n>0 then return end
 local text
 if view=='browse' then
  text=self.shoppingSearchStatus or (self.shoppingListMode and 'This shopping list is empty. Search for an item to add it.' or 'Search by item name, then select a result to compare or buy.')
 elseif view=='vendor' then
  text=self.scanState.running and 'Scanning auctions. Vendor deals appear when processing finishes.' or
   self.db.latestScan and 'No below-vendor deals found in the latest scan. Items without a known vendor value are excluded.' or 'Scan the Auction House to find below-vendor deals.'
 elseif view=='shopping' then text='No saved items yet. Find an item in Shopping, then choose ADD TO LIST.'
 elseif view=='my auctions' then text='No listings loaded. Click REFRESH MY AUCTIONS.'
 elseif view=='selling' then text='No sellable items found in your bags.' end
 if text then
  self.emptyMessage:ClearAllPoints();self.emptyMessage:SetPoint('TOPLEFT',view=='browse' and 250 or 45,-275)
  self.emptyMessage:SetWidth(view=='browse' and 735 or 940);self.emptyMessage:SetText(text);self.emptyMessage:Show()
 end
end

