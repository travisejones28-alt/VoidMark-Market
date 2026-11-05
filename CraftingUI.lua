local _,M=...
local function button(parent,text,x,w,fn)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetPoint('TOPLEFT',x,0);b:SetSize(w,26)
  b:SetText(text);b:SetScript('OnClick',fn);return b
end
function M:InitializeCraftingUI()
  if self.craftAction then return end
  local f=CreateFrame('Frame',nil,self.window);self.craftAction=f;f:SetPoint('BOTTOMLEFT',18,18);f:SetSize(998,28)
  button(f,'READ PROFESSION',0,145,function() self:CaptureProfession() end)
  button(f,'RECALCULATE',150,120,function() self:RebuildCrafting() end)
  button(f,'MATERIAL PLAN',275,125,function() self:BuildCraftShopping();self:SetView('materials') end)
  button(f,'ALL METHODS',405,115,function() self:SetView('goldmaking') end)
  local e=CreateFrame('EditBox',nil,f,'InputBoxTemplate');self.craftQuantity=e
  e:SetPoint('TOPLEFT',535,-1);e:SetSize(45,24);e:SetAutoFocus(false);e:SetText('1')
  e:SetScript('OnEscapePressed',function(w) w:ClearFocus() end)
  self.planCraftButton=button(f,'SET CRAFTS',590,110,function()
    local row=self.selectedRow;local ok,why=self:SetCraftPlan(row and row.recipe and row.recipe.id,tonumber(e:GetText()))
    self:Print(ok and 'Project saved (0 removes it).' or why)
  end)
  self.inspectCraftButton=button(f,'CALCULATIONS',705,125,function() self:ShowCraftCalculations(self.selectedRow) end)
  button(f,'CRAFTING',835,100,function() self:SetView('crafting') end)
  button(f,'NEXUS',940,55,function() local ok,e=self:ReadNexusRecipes();if not ok then self:Print(e) end end)
  f:Hide()
end
function M:CraftCalculationText(row)
  if not row then return 'Select a crafting opportunity.' end
  if not row.recipe then return row.reason or 'No crafting calculation selected.' end
  -- Recompute rather than displaying a stale row's price after a scan/bag change.
  row=self:EvaluateCraft(row.recipe,row.crafts or 1)
  local function money(v) return v and self:Money(v) or 'Unavailable' end
  local lines={row.name..' | '..row.profession,row.status..': '..(row.reason or ''),
    'Crafts '..row.crafts..' | output '..row.quantity,
    'Material replacement cost '..money(row.cost)..' | cash acquisition '..money(row.cashCost),
    'Buy finished '..money(row.buyFinished)..' | make-versus-buy saving '..money(row.makeSaving),
    'Sale/unit '..money(row.price)..' | gross '..money(row.gross)..' | AH cut '..money(row.fee),
    'Deposit loss allowance '..money(row.depositReserve)..' (not a native deposit quote)',
    'Net if sold '..money(row.netIfSold)..' | risk-adjusted net '..money(row.net),
    'Sale scenario factor '..self:PercentText(row.saleFactor or 0)..' (liquidity proxy, NOT measured sale probability)',
    'ROI '..self:PercentText(row.roi or 0)..' | scenario breakeven/output '..money(row.breakeven),
    'Inventory is current character bags only. Owned materials are NOT free in profit calculations.',
    row.inventoryReason or '', '', 'MATERIAL COST DETAILS'}
  local ids={};for id in pairs(row.materials or {}) do ids[#ids+1]=id end;table.sort(ids)
  for _,id in ipairs(ids) do
    local q=row.materials[id];local cash=row.shopping and row.shopping[id]
    lines[#lines+1]=string.format('Item %d: need %d | owned used %d | missing %d | %s | %s',id,q.quantity,
      row.owned and row.owned[id] or 0,cash and cash.quantity or 0,q.source,money(q.totalCost))
    for _,t in ipairs(q.tiers) do lines[#lines+1]='  '..t.quantity..' units @ '..money(t.unitPrice)..' = '..money(t.cost) end
    if q.surplus>0 then lines[#lines+1]='  Whole-stack surplus: '..q.surplus..'; no assumed resale credit' end
  end
  lines[#lines+1]='';lines[#lines+1]='INTERMEDIATE CRAFTS'
  for _,s in ipairs(row.steps or {}) do lines[#lines+1]=s end
  lines[#lines+1]='';lines[#lines+1]='ACTUAL BAGS ALLOCATED (including owned intermediate items)'
  for id,n in pairs(row.owned or {}) do if n>0 then lines[#lines+1]='Item '..id..': '..n end end
  lines[#lines+1]='CASH PURCHASES'
  for id,q in pairs(row.shopping or {}) do lines[#lines+1]='Item '..id..': '..q.quantity..' needed | '..money(q.totalCost)..' | '..q.source end
  lines[#lines+1]='';lines[#lines+1]='Known recipes only for chains; max depth 8, 128 nodes, three alternatives/item. Not a global optimizer.'
  return table.concat(lines,'\n')
end
function M:ShowCraftCalculations(row)
  if not self.craftDetailWindow then
    local f=CreateFrame('Frame',nil,UIParent,'BackdropTemplate');self.craftDetailWindow=f
    f:SetSize(800,580);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetClampedToScreen(true);f:EnableMouse(true)
    f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Tooltips\\UI-Tooltip-Border',edgeSize=14})
    f:SetBackdropColor(0.03,0.02,0.06,1);f:SetBackdropBorderColor(0.5,0.3,0.8,1)
    button(f,'CLOSE',700,90,function() f:Hide() end)
    local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',16,-35);scroll:SetSize(750,520)
    local child=CreateFrame('Frame',nil,scroll);child:SetSize(745,520);scroll:SetScrollChild(child);self.craftDetailChild=child
    local text=child:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');self.craftDetailText=text
    text:SetPoint('TOPLEFT');text:SetWidth(735);text:SetJustifyH('LEFT');text:SetJustifyV('TOP')
  end
  self.craftDetailText:SetText(self:CraftCalculationText(row))
  self.craftDetailChild:SetHeight(math.max(520,self.craftDetailText:GetStringHeight()+20));self.craftDetailWindow:Show()
end
function M:RenderCraftingUI(view)
  self:InitializeCraftingUI();self.craftAction:Show();self.tableFrame:Show();self.detail:Show()
  self.craftQuantity:SetShown(view=='crafting');self.planCraftButton:SetShown(view=='crafting')
  self.inspectCraftButton:SetShown(view~='materials')
  local source,headers
  if view=='crafting' then
    source=self:GetCraftRows(self.db.settings.filter,self.db.settings.sort)
    headers={'Crafting Intelligence','Profession','Cost','Sell/unit','Net est.','ROI','Confidence','Crafts / state'}
  elseif view=='materials' then
    source=(self.craftShopping or self:BuildCraftShopping()).rows
    headers={'Required material','Item ID','Owned used','Missing','Buy cost','Cap/unit','Source','State'}
  else source=self:GetGoldmakingRows();headers={'Gold-making opportunity','Method','Cost','Net est.','ROI','Quantity','Confidence','Score'} end
  local pages=math.max(1,math.ceil(#source/12));self.page=math.min(self.page or 1,pages)
  self.pageText:SetText(self.page..' / '..pages..' ('..#source..')')
  for i,h in ipairs(headers) do self.headings[i]:SetText(h) end
  for i,widget in ipairs(self.rows) do
    local r=source[(self.page-1)*12+i];widget.data=r;widget:SetShown(r~=nil)
    if r then
      widget.selected:SetShown(self.selectedRow==r);widget.icon:SetTexture(self:RowItemIcon(r,r.itemID))
      local function money(v) return v and self:Money(v) or '--' end
      local cells
      if view=='crafting' then cells={r.name,r.profession,money(r.cost),money(r.price),money(r.net),
        r.roi and self:PercentText(r.roi) or '--',r.confidence or '--',r.worthCrafting..' / '..r.status}
      elseif view=='materials' then cells={r.name,r.itemID,r.owned,r.missing,money(r.cost),money(r.maxUnit),r.source,r.missing==0 and 'OWNED' or 'VERIFY LIVE'}
      else cells={r.name,r.kind,money(r.cost),money(r.net),self:PercentText(r.roi),r.quantity,r.confidence,r.score} end
      for j,c in ipairs(cells) do widget.cols[j]:SetText(tostring(c)) end
    end
  end
  if view=='crafting' then
    local r=self.selectedRow;local p=r and self.db.craftPlans[self.characterID..'/'..tostring(r.id)]
    self.detail:SetText((self.craftingBusy and 'Calculating recipes across frames...\n' or '')..
      (self.recipeDiagnostic or 'Open each profession to capture recipes. Legacy API exposes learned recipes only.')..
      '\nFilter by recipe, profession, item ID or status. Select a row, enter crafts, then SET CRAFTS (0 removes). '..
      '\n'..(r and (r.name..' | '..(r.reason or r.status)..' | planned crafts '..(p and p.crafts or 0)) or 'Select a row for exact calculations.')..
      '\nOwned materials retain replacement value. No purchase or craft is automated. Unknown values stay unpriced.')
  elseif view=='materials' then
    local p=self.craftShopping;local names={};for _,v in ipairs(p.projects) do names[#names+1]=v.name..' x'..v.crafts end
    self.detail:SetText('Projects: '..table.concat(names,', ')..'\nAcquisition '..self:Money(p.cost)..' | '..(p.complete and 'Plan priced' or 'INCOMPLETE / BLOCKED')..
      '\n'..table.concat(p.errors,'; ')..'\nCaps apply one item at a time; recalculate after prices change. Shared bags are allocated once.'..
      '\nUse the native AH to purchase missing materials. Existing SHOPPING watchlists remain separate.')
  else self.detail:SetText('Ranked passing opportunities using existing bankroll limits. Snapshot estimates require live verification.'..
    '\nCrafting and disenchant estimates include a conservative liquidity scenario; flips retain the existing resale model.'..
    '\nDisenchanting requires a supplied verified distribution; farming comparisons require measured yield through PricingAPI.'..
    '\nNo recipes or prices are invented. Nexus owns routes and navigation; Market supplies valuations.') end
end
