local _,M=...
-- Inspect all local markets, independently of the capped/resale-ranked sniper list.
function M:GetVendorRows(filter)
  local out={};local needle=(filter or ''):lower()
  for _,m in pairs(self.db.market or {}) do
    local d=m.depth
    if not m.archived and not m.cacheUntrusted and m.lastSeen and m.lastSeen>0
      and m.lastSeen>=(self.db.lastDepthSnapshotAt or 0) and d and d.at==m.lastSeen then
      local vendor=m.vendorPrice or 0
      if GetItemInfo then
        local _,_,_,_,_,_,_,_,_,_,value=GetItemInfo(m.itemLink or m.itemID)
        if tonumber(value) then vendor=tonumber(value);m.vendorPrice=vendor end
      end
      local name=m.name or tostring(m.itemID)
      if vendor>0 and (needle=='' or name:lower():find(needle,1,true) or tostring(m.itemID)==needle) then
        local qty,cost,best=0,0,nil
        for _,lot in ipairs(d.lots or {}) do
          if self:Finite(lot.quantity,1,100000) and self:Finite(lot.cost,1,1e12)
            and self:Finite(lot.count,1,1e7) and lot.cost<vendor*lot.quantity then
            qty=qty+lot.quantity*lot.count;cost=cost+lot.cost*lot.count
            if not best or lot.cost/lot.quantity<best.cost/best.quantity then best=lot end
          end
        end
        if best then
          local e=self:Economics(m,best.cost,best.quantity,'vendor')
          local pass,blocks=self:CheckRisk(m,e)
          out[#out+1]={marketKey=m.marketKey,itemID=m.itemID,name=name,kind='vendor',
            floor=best.cost/best.quantity,vendorPrice=vendor,quantity=qty,totalCost=cost,
            totalProfit=vendor*qty-cost,buyQuantity=best.quantity,economics=e,pass=pass,blocks=blocks,
            fairValue=m.fairValue,at=m.lastSeen,confidence=m.confidence,
            status=not self:MarketFresh(m) and 'STALE - rescan' or d.incomplete and 'Partial depth' or 'Recheck live'}
        end
      end
    end
  end
  table.sort(out,function(a,b) return a.totalProfit==b.totalProfit and tostring(a.marketKey)<tostring(b.marketKey) or a.totalProfit>b.totalProfit end)
  return out
end
