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
          local suffix=self:Suffix(info.hyperlink)
          local key=suffix and self:Key(info.itemID,suffix) or nil
          local qty=tonumber(info.stackCount) or 1
          if self:Finite(qty,1,1e6) and qty%1==0 then
            local plan=key and self:BuildSellPlan(key,qty) or
              {marketKey=nil,quantity=qty,status='VARIANT UNKNOWN',
               reason='Item hyperlink or variant unavailable; cannot select a safe price'}
            local m=key and self.db.market[key]
            plan.itemID=info.itemID
            plan.name=m and m.name or info.itemName or (GetItemInfo and GetItemInfo(info.itemID)) or
              ('Item '..tostring(info.itemID))
            plan.quantity=qty;plan.bag=currentBag;plan.slot=currentSlot
            plan.itemLink=info.hyperlink
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
    self.sellingRows=rows;self:RefreshUI()
  end)
end
function M:RequestOwnedAuctionsDiagnostic()
  self:QueueRequest({id='owned',kind='owned',priority=30,done=function() M:CaptureOwnedAuctions() end,
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
        rows[#rows+1]={auctionID=info.auctionID,marketKey=key,name=m and m.name or ('Item '..info.itemKey.itemID),quantity=qty,
          unit=unit,timeLeft=info.timeLeftSeconds or info.timeLeft,status=info.status,deposit=info.depositAmount,
          floor=m and m.latest and m.latest.meaningfulFloor,reason='Snapshot comparison only; refresh item before deciding'}
      end
      if debugprofilestop()-start>=4 then return false end
    end
  end,function() self.ownedRows=rows; self:RefreshInventory(); self:RefreshUI() end)
end
function M:AnalyzeOwnedLive(row)
  local m=self.db.market[row.marketKey]; if not m then return end
  self:Search(m,60,function(result)
    local competitor=result.rows[1] and result.rows[1].unit
    row.liveAt=time(); row.competition=competitor
    if not competitor then row.reason='No competing supply; hold your auction'
    elseif competitor>=row.unit then row.reason='Your price is competitive; hold'
    else
      local reduction=(row.unit-competitor)*row.quantity
      local A=C_AuctionHouse; local cost
      if A.GetCancelCost then local ok,v=pcall(A.GetCancelCost,row.auctionID); if ok then cost=tonumber(v) end end
      row.cancelCost=cost
      row.reason=string.format('Undercut %.1f%%; repricing reduces revenue by %s. %s',100*(row.unit-competitor)/math.max(1,row.unit),self:Money(reduction),
        cost and ('Cancel fee '..self:Money(cost)..'; deposit loss '..(row.deposit and self:Money(row.deposit) or 'unknown')..'. Review demand before churn.') or 'Cancel/deposit cost unknown; hold until verified.')
    end
    self:RefreshUI()
  end,function(e) row.reason=e; self:RefreshUI() end)
end
M:RegisterHandler('BAG_UPDATE_DELAYED',function(self) self.bagsDirty=true end)
M:RegisterHandler('GET_ITEM_INFO_RECEIVED',function(self) self.bagsDirty=true end)
M:RegisterHandler('AUCTION_CANCELED',function(self,_,id)
  self:AddLedger('cancelled',{auctionID=id,status='observed',evidence='Observed AUCTION_CANCELED; lost deposit unknown'})
end)
M:RegisterHandler('AUCTION_HOUSE_AUCTION_CREATED',function(self,_,id)
  self:AddLedger('posted',{auctionID=id,status='observed',evidence='Observed creation; price/deposit captured only if supplied by client'})
end)
