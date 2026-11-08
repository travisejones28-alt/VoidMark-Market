local _,M=...
local function itemID(link) return type(link)=='string' and tonumber(link:match('item:(%d+)')) end
function M:InitializeCrafting()
  for _,k in ipairs({'recipes','craftPlans','vendorMaterials'}) do
    if type(self.db[k])~='table' then self.db[k]={} end
  end
  self.craftRows={};self.craftRevision=(self.craftRevision or 0)+1
end
function M:RegisterRecipe(r)
  if not self.db or self.persistenceBlocked then return false,'Database unavailable or read-only' end
  if type(r)~='table' or type(r.id)~='string' or #r.id>120 or type(r.name)~='string' or #r.name>200
    or type(r.profession)~='string' or #r.profession>100 or not self:Finite(r.itemID,1,1e9) or r.itemID%1~=0
    or not self:Finite(r.output,1,1000) or r.output%1~=0 or type(r.reagents)~='table' or #r.reagents==0 or #r.reagents>20 then return false,'Incomplete recipe' end
  local reagents={};local seen={}
  for _,v in ipairs(r.reagents) do
    if type(v)~='table' or not self:Finite(v.itemID,1,1e9) or v.itemID%1~=0
      or not self:Finite(v.quantity,1,10000) or v.quantity%1~=0 or seen[v.itemID] then return false,'Invalid reagent' end
    seen[v.itemID]=true;reagents[#reagents+1]={itemID=v.itemID,quantity=v.quantity}
  end
  local old=self.db.recipes[r.id];local count=0
  if not old then for _ in pairs(self.db.recipes) do count=count+1 end end
  if count>=5000 then return false,'Recipe cache limit reached' end
  local learned=old and old.learnedBy or {}
  if r.learned~=nil then learned[self.characterID]=r.learned==true or nil end
  self.db.recipes[r.id]={id=r.id,name=r.name,profession=r.profession,itemID=r.itemID,output=r.output,
    reagents=reagents,learnedBy=learned,at=time(),source=r.source or 'profession API',spellID=r.spellID}
  self.recipeByItem=nil
  return true
end
function M:KnownRecipe(r) return r and r.learnedBy and r.learnedBy[self.characterID]==true end
function M:RecipeCandidates(item)
  if self.recipeByItem then return self.recipeByItem[item] or {} end
  local out={}
  for _,r in pairs(self.db.recipes) do if r.itemID==item and self:KnownRecipe(r) then out[#out+1]=r end end
  table.sort(out,function(a,b) return a.id<b.id end)
  return out
end
function M:OwnedMaterial(item)
  local fn=C_Item and C_Item.GetItemCount or GetItemCount
  if type(fn)~='function' then return nil end
  local ok,n=pcall(fn,item,false,false,false) -- bags only; no stale alt/bank promises
  if ok and self:Finite(n,0,10000000) then return math.floor(n) end
  return nil
end
-- Read only complete learned recipes for the logged-in Nexus character.
-- Imported recipes never supply invented material costs or sale evidence.
function M:ReadNexusRecipes()
 local n=_G.VoidMarkNexus;local c=n and n.character
 if self.persistenceBlocked or not c or n.economy~=self.economyID or c.name~=UnitName('player') or type(c.professions)~='table' then
  return false,'No matching Nexus profession cache for this character'
 end
 local captured=0
 local co=coroutine.create(function()
  for _,prof in pairs(c.professions) do
   for _,r in pairs(prof.recipes or {}) do
    if r.learned and not r.incomplete and not r.bound and not r.disabled and r.outputMin==r.outputMax and type(r.reagents)=='table' then
     local id=r.spell and ('spell:'..r.spell) or (prof.name..':'..tostring(r.output)..':'..r.name)
     local cached=self.db.recipes[id]
     if not cached or (cached.source=='VoidMark Nexus' and (cached.at or 0)<(r.at or 0)) or not self:KnownRecipe(cached) then
      local reagents={};for _,v in ipairs(r.reagents) do reagents[#reagents+1]={itemID=v.id,quantity=v.qty} end
      if self:RegisterRecipe({id=id,name=r.name,profession=prof.name,itemID=r.output,output=r.outputMin,
       reagents=reagents,source='VoidMark Nexus',learned=true,spellID=r.spell}) then captured=captured+1 end
     end
    end
    coroutine.yield()
   end
  end
 end)
 self:AddJob('nexus-recipes',function(start)
  for i=1,15 do local ok,err=coroutine.resume(co);if not ok then error(err) end
   if coroutine.status(co)=='dead' then return true end
   if debugprofilestop()-start>=3 then break end
  end
 end,function() self.recipeDiagnostic=captured..' recipes read from Nexus';self:RebuildCrafting() end)
 return true
end
function M:CaptureProfession()
  if not self.db then return end
  local legacy=type(GetNumTradeSkills)=='function' and type(GetTradeSkillReagentItemLink)=='function'
    and type(GetTradeSkillItemLink)=='function' and type(GetTradeSkillInfo)=='function'
    and type(GetTradeSkillNumReagents)=='function' and type(GetTradeSkillReagentInfo)=='function'
    and type(GetTradeSkillNumMade)=='function' and type(GetTradeSkillLine)=='function'
  local modern=C_TradeSkillUI and type(C_TradeSkillUI.GetAllRecipeIDs)=='function'
    and type(C_TradeSkillUI.GetRecipeInfo)=='function' and type(C_TradeSkillUI.GetRecipeSchematic)=='function'
    and type(C_TradeSkillUI.GetRecipeItemLink)=='function'
  local ids,profession,n
  if legacy then
    local ok,v=pcall(GetNumTradeSkills);if not ok or not self:Finite(v,0,5000) then return end
    n=v;profession=GetTradeSkillLine() or 'Unknown'
  elseif modern then
    local ok,v=pcall(C_TradeSkillUI.GetAllRecipeIDs);if not ok or type(v)~='table' or #v>5000 then return end
    ids=v;n=#ids;profession='Profession'
    if C_TradeSkillUI.GetTradeSkillLine then
      local good,p=pcall(C_TradeSkillUI.GetTradeSkillLine);if good and type(p)=='table' then profession=p.professionName or profession end
    end
  else self:Log('CRAFTING','No supported profession reader; open a profession and use /vmm craftscan');return end
  local i,accepted,skipped=1,0,0
  self:AddJob('recipes',function(start)
    for _=1,8 do
      if i>n then return true end
      local index=i;i=i+1
      local ok,r=pcall(function()
        if legacy then
          local name,kind=GetTradeSkillInfo(index)
          if not name or kind=='header' then return nil end
          local outputItem=itemID(GetTradeSkillItemLink(index));local low,high=GetTradeSkillNumMade(index)
          if not outputItem or not low or high~=low then return nil end -- uncertain yields unsupported
          local nr=GetTradeSkillNumReagents(index);if not self:Finite(nr,1,20) then return nil end
          local reagents={}
          for j=1,nr do
            local _,_,qty=GetTradeSkillReagentInfo(index,j);local id=itemID(GetTradeSkillReagentItemLink(index,j))
            if not id or not qty then return nil end;reagents[#reagents+1]={itemID=id,quantity=qty}
          end
          return {id=profession..':'..outputItem..':'..name,name=name,profession=profession,itemID=outputItem,
            output=low,reagents=reagents,learned=true,source='legacy profession API'}
        end
        local id=ids[index];local info=C_TradeSkillUI.GetRecipeInfo(id);local sc=C_TradeSkillUI.GetRecipeSchematic(id,false)
        if type(info)~='table' or type(sc)~='table' or not sc.quantityMin or sc.quantityMin~=sc.quantityMax then return nil end
        local reagents={}
        for _,slot in ipairs(sc.reagentSlotSchematics or {}) do
          -- Reject optional/recraft/quality-choice structures rather than guess.
          if not slot.quantityRequired or slot.quantityRequired<=0 or type(slot.reagents)~='table' or #slot.reagents~=1 then return nil end
          reagents[#reagents+1]={itemID=slot.reagents[1].itemID,quantity=slot.quantityRequired}
        end
        return {id='spell:'..id,spellID=id,name=info.name,profession=profession,
          itemID=itemID(C_TradeSkillUI.GetRecipeItemLink(id)),output=sc.quantityMin,reagents=reagents,
          learned=info.learned==true,source='feature-detected schematic API'}
      end)
      if ok and r and self:RegisterRecipe(r) then accepted=accepted+1 else skipped=skipped+1 end
      if debugprofilestop()-start>=4 then return false end
    end
  end,function()
    self.recipeDiagnostic=string.format('%d recipes captured, %d headers/unsupported/incomplete rows skipped',accepted,skipped)
    self:Log('CRAFTING',self.recipeDiagnostic);self:RebuildCrafting()
  end)
end
function M:CaptureVendorMaterials()
  if not self.db or self.persistenceBlocked or type(GetMerchantNumItems)~='function'
    or type(GetMerchantItemInfo)~='function' or type(GetMerchantItemLink)~='function' then return end
  local ok,n=pcall(GetMerchantNumItems);if not ok or not self:Finite(n,0,500) then return end
  local count=0
  for id,v in pairs(self.db.vendorMaterials) do
    if type(v)~='table' or not self:Finite(v.at,time()-86400,time()) then self.db.vendorMaterials[id]=nil
    else count=count+1 end
  end
  for i=1,n do
    local good,_,_,price,bundle,stock,_,_,extended=pcall(GetMerchantItemInfo,i)
    local linkOK,link=pcall(GetMerchantItemLink,i);local id=linkOK and itemID(link)
    if good and id and (self.db.vendorMaterials[id] or count<1000) and stock==-1 and extended==false and self:Finite(price,1,1e12) and self:Finite(bundle,1,10000) then
      if not self.db.vendorMaterials[id] then count=count+1 end
      self.db.vendorMaterials[id]={price=price/bundle,bundle=bundle,at=time(),character=self.characterID}
    end
  end
  self:RebuildCrafting()
end
M:RegisterHandler('TRADE_SKILL_SHOW',function(self) self:CaptureProfession() end)
M:RegisterHandler('TRADE_SKILL_LIST_UPDATE',function(self) self:CaptureProfession() end)
M:RegisterHandler('TRADE_SKILL_CLOSE',function(self) self:CancelJob('recipes') end)
M:RegisterHandler('MERCHANT_SHOW',function(self) self:CaptureVendorMaterials() end)
-- Bag changes (looting, gathering) used to rebuild every recipe each time.
-- Now crafting is only marked stale; it rebuilds when a crafting screen shows.
local craftViews={crafting=true,goldmaking=true,materials=true}
M:RegisterHandler('BAG_UPDATE_DELAYED',function(self)
 if not self.db then return end
 if craftViews[self.view] and self.window and self.window:IsShown() then self:RebuildCrafting() else self.craftingStale=true end
end)
function M:RebuildCraftingIfStale(view)
 if craftViews[view] and self.craftingStale then self.craftingStale=nil;self:RebuildCrafting() end
end
