local _,M=...
M.sellingRows={}; M.ownedRows={}
function M:RefreshInventory()
  self.sellingRows={}
  if not C_Container or type(C_Container.GetContainerItemInfo)~='function'
    or type(C_Container.GetContainerNumSlots)~='function' then return end
  local bag,slot=0,1; local rows={}
  self:AddJob('bags',function(start)
    for j=1,25 do
      if bag>4 then return true end
      local ok,count=pcall(C_Container.GetContainerNumSlots,bag)
      if not ok or not self:Finite(count,0,200) then
        -- Never present a partial inventory as a complete pricing result.
        rows={};self:Log('SELL','Bag slot query unavailable; pricing cancelled');return true
      end
      if slot>count then bag=bag+1;slot=1
      else
        local currentBag,currentSlot=bag,slot;slot=slot+1
        local success,info=pcall(C_Container.GetContainerItemInfo,currentBag,currentSlot)
        if success and type(info)=='table' and info.itemID and not info.isBound then
          local key=self:LinkIdentity(info.hyperlink,info.itemID)
          local qty=tonumber(info.stackCount) or 1
          if self:Finite(qty,1,1e6) and qty%1==0 then
            local plan=key and self:BuildSellPlan(key,qty) or
              {marketKey=nil,quantity=qty,status='VARIANT UNKNOWN',
               reason='Item hyperlink or variant unavailable; cannot select a safe price'}
            local m=key and self.db.market[key]
            plan.itemID=info.itemID
            plan.name=m and m.name or info.itemName or (GetItemInfo and GetItemInfo(info.itemID)) or
              ('Item '..tostring(info.itemID))
            -- Forever's links drop the suffix, so a scan can file another suffix's
            -- price under this item. Use the real name from the item's tooltip and
            -- never offer a price that belongs to a different suffix.
            local full=self.BagItemFullName and self:BagItemFullName(currentBag,currentSlot)
            if full then
              local state,sf=self:VariantPrice(key,full,self:LinkName(info.hyperlink))
              if state=='suffix' then
                plan.price=sf.floor;plan.suffixPrice=sf.floor;plan.reason='Last scan price for this suffix'
              elseif state=='none' then
                plan.variantMismatch=m and m.name or true;plan.price=nil;plan.reason='No scan price for this suffix yet'
              end
              plan.name=full
            end
            -- The AH's own key for this exact item (with its suffix): used for
            -- your settings, post history and what you paid, so suffixes never share.
            local ahKey=self:BagAHKey(currentBag,currentSlot,info.itemID)
            if ahKey~=nil and ahKey~=key then plan.linkKey=key;plan.marketKey=ahKey end
            plan.quantity=qty;plan.bag=currentBag;plan.slot=currentSlot
            plan.itemLink=info.hyperlink
            plan.icon=info.iconFileID
            plan.confidence=plan.confidence or 'Unknown'
            plan.stale=not plan.price
            rows[#rows+1]=plan
          end
        end
      end
      if debugprofilestop()-start>=4 then return false end
    end
  end,function()
    table.sort(rows,function(a,b)
      if (a.price~=nil)~=(b.price~=nil) then return a.price~=nil end
      return tostring(a.name)<tostring(b.name)
    end)
    self.sellingRows=rows
    if self.AfterPostRefresh then self:AfterPostRefresh(rows) end
    self:RefreshUI()
  end)
end
function M:RequestOwnedAuctionsDiagnostic()
  -- You're looking at Listings and waiting: ahead of list/name searches (only a
  -- purchase you're in the middle of, priority 90, goes first).
  self:QueueRequest({id='owned',kind='owned',priority=85,done=function() M:CaptureOwnedAuctions() end,
    fail=function(e) M:Log('OWNED',e); M:Print(e) end})
end
function M:CaptureOwnedAuctions()
  local A=C_AuctionHouse; local rows={}; local n=0
  local all
  if A.GetOwnedAuctions then local ok,v=pcall(A.GetOwnedAuctions); if ok and type(v)=='table' then all=v; n=#v end end
  if not all and A.GetNumOwnedAuctions then local ok,v=pcall(A.GetNumOwnedAuctions); if ok then n=tonumber(v) or 0 end end
  local i=1
  self:AddJob('owned',function(start)
    for j=1,40 do
      if i>n then return true end
      local info=all and all[i]; if not all and A.GetOwnedAuctionInfo then local ok,v=pcall(A.GetOwnedAuctionInfo,i); if ok then info=v end end
      i=i+1
      if type(info)=='table' and type(info.itemKey)=='table' then
        local key=self:Key(info.itemKey.itemID,info.itemKey.itemSuffix,info.itemKey.itemLevel,info.itemKey.battlePetSpeciesID)
        local m=self.db.market[key]; local qty=tonumber(info.quantity) or 1
        local unit=tonumber(info.unitPrice) or (tonumber(info.buyoutAmount) or 0)/math.max(1,qty)
        rows[#rows+1]={auctionID=info.auctionID,itemKey=info.itemKey,itemID=info.itemKey.itemID,marketKey=key,name=self:OwnedAuctionName(key,m,info),quantity=qty,
          unit=unit,timeLeft=info.timeLeftSeconds or info.timeLeft,status=info.status,action='INSPECT',deposit=info.depositAmount,
          floor=m and m.latest and m.latest.meaningfulFloor,reason='Snapshot comparison only; refresh item before deciding'}
      end
      if debugprofilestop()-start>=4 then return false end
    end
  end,function() if self.CarryOwnedVerdicts then self:CarryOwnedVerdicts(self.ownedRows,rows) end
    self.ownedRows=rows; if self.UpdateFlipListings then self:UpdateFlipListings(rows) end
    if not self.persistenceBlocked then
      -- Kept across reloads/logins so sale alerts know your listing prices.
      local snap={}
      for i=1,math.min(#rows,300) do local o=rows[i];snap[i]={auctionID=o.auctionID,name=o.name,unit=o.unit,quantity=o.quantity,marketKey=o.marketKey,status=o.status} end
      self.db.ownedSnapshot={at=time(),rows=snap}
    end; self:RefreshInventory(); self:RefreshUI() end)
end
function M:AnalyzeOwnedLive(row)
  local market=row and self.db.market[row.marketKey]
  if not market and row and row.itemKey then market=row.itemKey end
  if not market or not row.auctionID then
    if row then row.action='HOLD';row.reason='Cannot safely identify this auction or its variant' end
    self:RefreshUI();return
  end
  row.action='CHECKING';row.reason='Waiting for complete live search results'
  self:Search(market,60,function(result)
    -- ReadSearch already removes own commodity quantity and ignores own regular listings.
    local competitor=result.rows[1] and result.rows[1].unit
    local A=C_AuctionHouse;local cost=nil
    if type(A.GetCancelCost)=='function' then
      local ok,value=pcall(A.GetCancelCost,row.auctionID)
      if ok and self:Finite(value,0,1e12) then cost=value end
    end
    self:ApplyOwnedCompetition(row,competitor)
    row.cancelCost=cost
    local outcome=self:AssessOwnedRepost(row,competitor,cost)
    row.action=outcome.action;row.reason=outcome.reason
    row.proposedUnit=outcome.proposedUnit;row.repriceDifference=outcome.revenueDecrease
    self:SyncOwnedVerdict(row)
    self:RefreshUI()
  end,function(e)
    row.action='HOLD';row.reason='Live competitor search failed: '..tostring(e)
    self:SyncOwnedVerdict(row)
    self:RefreshUI()
  end)
end
M:RegisterHandler('BAG_UPDATE_DELAYED',function(self) self.bagsDirty=true end)
M:RegisterHandler('GET_ITEM_INFO_RECEIVED',function(self,_,id)
  if self.view~='selling' or not (self.window and self.window:IsShown()) then return end
  id=tonumber(id)
  for _,r in ipairs(self.sellingRows or {}) do
    if r.itemID==id and type(r.name)=='string' and r.name:match('^Item %d') then self.bagsDirty=true;return end
  end
end)
M:RegisterHandler('AUCTION_CANCELED',function(self,_,id)
  self:AddLedger('cancelled',{auctionID=id,status='observed',evidence='Observed AUCTION_CANCELED; lost deposit unknown'})
end)
M:RegisterHandler('AUCTION_HOUSE_AUCTION_CREATED',function(self,_,id)
  self:AddLedger('posted',{auctionID=id,status='observed',evidence='Observed creation; price/deposit captured only if supplied by client'})
end)

-- Name for one of your auctions: the AH's own name for its exact key (with the
-- suffix). A scanned name is only used when it isn't another suffix's.
function M:OwnedAuctionName(key,m,info)
 local id=info and info.itemKey and info.itemKey.itemID
 local full=self.KeyFullName and self:KeyFullName(key)
 if full then return full end
 local base=self:ItemName(id) or (GetItemInfo and GetItemInfo(id))
 local scanned=m and m.name
 if scanned and not m.mixedVariants and (not base or self:NameScore(scanned,base)>0) then return scanned end
 return base or scanned or ('Item '..tostring(id))
end

-- AH item key of a bag item, only when it carries a suffix the link lacks.
function M:BagAHKey(bag,slot,itemID)
 local A=C_AuctionHouse
 if not (A and A.GetItemKeyFromItem and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end
 local ok,k=pcall(function() return A.GetItemKeyFromItem(ItemLocation:CreateFromBagAndSlot(bag,slot)) end)
 if not ok or type(k)~='table' or k.itemID~=itemID or (tonumber(k.itemSuffix) or 0)==0 then return nil end
 return self:Key(k.itemID,k.itemSuffix,k.itemLevel or 0,k.battlePetSpeciesID or 0)
end
