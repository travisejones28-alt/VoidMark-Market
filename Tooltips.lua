local _, M = ...
-- Passive item tooltip pricing. Cached AH asks are NOT live quotations.
-- Never triggers an auction search or sends an addon message on mouseover.
function M:TooltipMarketForLink(link)
  if not self.db or type(link)~='string' then return end
  local itemString=link:match('item:([%d:%-]+)')
  if not itemString then return end
  local id=tonumber(itemString:match('^(%d+)'))
  if not id then return end
  -- Prefer an explicitly known exact item hyperlink. Generic IDs are safe
  -- only when the item has a single stored market variant.
  local exact
  local variants={}
  local lookup=self.itemIndex and self.itemIndex[id] or {}
  for _,key in ipairs(lookup) do
    local m=self.db.market[key]
    if type(m)=='table' and m.itemID==id then
      variants[#variants+1]=m
      if m.itemLink==link then exact=m end
    end
  end
  if exact then return exact end
  if #variants==1 then return variants[1] end
  -- A nonvariant base ID can be used only if all stored variants are base IDs.
  if #variants>1 then return nil,'Multiple variants; select exact auction item' end
end
function M:AppendMarketTooltip(tooltip,link)
  if not tooltip or not self.db or not link then return end
  local market,reason=self:TooltipMarketForLink(link)
  if not market then
    if reason then tooltip:AddLine('VoidMark: '..reason,.75,.6,.9) end
    return
  end
  local latest=market.latest
  local floor=type(latest)=='table' and tonumber(latest.floor)
  local at=tonumber(market.lastSeen)
  if not self:Finite(floor,1,1e12) or not self:Finite(at,1,time()+300) then return end
  local age=math.max(0,time()-at)
  local fresh=self:MarketFresh(market) and not market.cacheUntrusted and not market.analysisIncomplete
  local ageText=age>=86400 and string.format('%dd %dh',math.floor(age/86400),math.floor(age%86400/3600))
    or age>=3600 and string.format('%dh %dm',math.floor(age/3600),math.floor(age%3600/60))
    or string.format('%dm',math.floor(age/60))
  tooltip:AddDoubleLine('VoidMark AH lowest (scan)',self:Money(floor),.7,.5,1,1,.87,.42)
  tooltip:AddLine((fresh and 'Cached scan' or 'STALE / UNVERIFIED')..' | '..ageText..' old',
    fresh and .6 or 1,fresh and .85 or .4,fresh and .6 or .4)
  tooltip:Show()
end
function M:InitializePriceTooltips()
  if self.tooltipHooked then return end
  self.tooltipHooked=true
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,function(tooltip,data)
      if tooltip~=GameTooltip then return end
      local link
      if tooltip.GetItem then
        local _,v=tooltip:GetItem()
        link=v
      end
      if link then
        local ok,err=pcall(M.AppendMarketTooltip,M,tooltip,link)
        if not ok then M:Log('TOOLTIP',err) end
      end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript('OnTooltipSetItem',function(tooltip)
      local _,link=tooltip:GetItem()
      if link then
        local ok,err=pcall(M.AppendMarketTooltip,M,tooltip,link)
        if not ok then M:Log('TOOLTIP',err) end
      end
    end)
  end
end
