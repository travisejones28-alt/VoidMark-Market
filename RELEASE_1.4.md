# VoidMark Market 1.4.0-beta — Crafting Intelligence

Adds crafting and quantity-aware acquisition analysis to the existing Forever
16001 terminal. Existing scanning, watchlists, ledger, portfolios, trading
limits, and click-controlled execution remain intact. Every login still starts
in Safe Mode. New material plans are advisory and never place transactions.

## New functionality

- Full scans retain bounded whole-stack acquisition books, excluding the current
  character's listings. Costs walk available stock rather than multiplying the
  floor price. Expensive tiers above four times the snapshot median are excluded
  from acquisition estimates. Incomplete depth is not quoted.
- A newly completed fresh scan invalidates acquisition stock absent from that
  generation. Cached snapshots do not establish fresh prices or resale evidence.
- Crafting Intelligence captures deterministic recipes from the open profession,
  computes replacement cost, bag-adjusted cash cost, buy-versus-make savings,
  AH fees, deposit allowance, net profit, ROI and breakeven. Owned materials retain
  economic value; they are not treated as free profit.
- Known intermediate recipes can replace expensive purchased intermediates.
  Shared reagents are priced together against available depth. Cycles, excessive
  branching and missing prices fail conservatively.
- Character-specific projects share one bag allocation and one acquisition book.
  Material plans show owned quantities, shortages, whole-stack costs and purchase
  ceilings. Aggregate projects also face capital and profit limits. A ceiling
  assumes other prices stay fixed: recalculate after changing one input.
- The purple terminal has a Crafting tab, sorting/filtering, project controls and
  a scrollable calculation breakdown. Existing Shopping watchlists are preserved.
- All Methods ranks eligible auction flips, material resales, vendor arbitrage
  and crafting. Disenchant analysis is conditional on an explicitly supplied,
  verified distribution; no unsupported results are fabricated.
- PricingAPI v1 provides local prices, quantities, timestamps, confidence,
  acquisition costs, crafting candidates and measured-yield farming comparisons.
  It performs no extra scans and requires no Nexus installation.

## Calculation assumptions and boundaries

All values are copper. Acquisition walks whole stacks in unit-price order; this
is a conservative feasible estimate, not a guaranteed cheapest combination of
stack sizes. It charges surplus units in full and assumes no resale credit.
Snapshots are not live quotes. Vendor offers must have been observed within 24
hours on this character, be unlimited and require money only. Actual availability,
location, reputation discount and current purchase price must be checked again.

Crafting net if sold = gross - configured AH cut - configured deposit allowance
- material replacement cost. Risk-adjusted net applies a scenario factor of
10–90%, based on the existing supply-activity proxy, to after-cut proceeds before
subtracting costs. This factor is **not a measured sale probability**. Unsold
inventory receives no credit in that scenario. The configured deposit allowance
is not a native deposit quote; the native AH remains authoritative.

Output supply limits, existing confidence/history/volatility rules, minimum
profit/ROI, gold reserve and transaction/item/portfolio limits apply. Crafting
search checks at most 50 batch sizes within the configured quantity cap and
stops at the first blocked size; this favors conservative recommendations over
finding every potential bulk discount. Alternatives are limited to three known
recipes per item, depth eight and 128 recursive visits per expansion. These are
bounded heuristics, not global optimization.

## In-game test procedure

1. Install the current ZIP, log in on Forever, and confirm `1.4.0-beta` and
   **SAFE MODE ON**. Do not delete SavedVariables. Verify existing ledger,
   watchlists, positions and settings are still present.
2. Open the AH and run `/vmm scan`. Existing history is retained, but old versions
   did not store acquisition books: one fresh successful scan is required.
   Resale estimates still need at least three independent observations and all
   configured evidence gates; repeating cached analysis cannot bypass them.
3. Open each profession. Run `/vmm craftscan` if needed, then `/vmm craft`.
   Compare captured reagent counts and output yields with the native window.
   If links were initially uncached, reopen the profession and capture again.
4. Select a recipe and click CALCULATIONS. Check material tiers, replacement
   versus cash cost, fees, deposit allowance, sale scenario and breakeven.
   Move some reagents into/out of bags and confirm cash requirements update
   while owned reagents retain value in profit calculations.
5. Enter a craft count and click SET CRAFTS for two recipes sharing a reagent.
   Run `/vmm materials`. Check shared bags are counted once and purchase costs
   rise when the cheap tier runs out. Use zero crafts to remove a project.
6. Run `/vmm gold` to review passing opportunities. Increase a reserve or lower
   a spend cap, recalculate, and confirm affected recommendations are blocked.
   No new panel should buy, post, disenchant or craft anything automatically.
7. `/reload`: confirm projects/recipes remain, original data is intact, and
   Safe Mode is back on. Check another character cannot consume these plans or
   this character's bags. Recheck Browse, Sniper, Sell, Ledger and Shopping.
8. Run `/vmm probe`, `/vmm diag`, or `/vmm report` for errors, capture counts and
   supported interfaces. Test scrolling, filters, sort modes and calculation
   window layout at your actual UI scale.

## Verified versus still requiring verification

121 deterministic regression tests pass locally in a Lua 5.1-compatible LuaJIT
runtime, including all 97 pre-existing cases. Coverage includes 90,000-row scan
processing, existing purchase safeguards, acquisition depth/own-auction handling,
craft arithmetic, shared inventory, chains/cycles, persistence, recipe adapters,
merchant restrictions, stale data, UI event mocks and the integration API.
CI runs the same suite with `lupa.lua51` (stock Lua 5.1) and verifies ZIP contents.

WoW Forever has not been executed in this development session. Profession return
shapes, actual visual layout, event timing and live game behavior require the
tests above. Feature detection is not a claim that Retail APIs behave identically
on Forever. The legacy reader only sees learned, visible recipes; the optional
schematic reader records learnable recipes only when the client exposes them.
Collapsed/filtered legacy lists may need expanding before capture. Enchanting's
separate Craft API, variable yields, optional/ranked reagents, cooldown feasibility,
specializations, trainer databases and cooldown costs are not modeled. Learned
status means last captured on this character; recapture after profession changes.
Only current bags are allocated, not bank or alt inventories.

The four requested reference ZIPs were identified but could not be downloaded in
this session, and their binary contents were not exposed by the file reader.
Consequently their code, databases, licenses and UI were **not reviewed**, and no
claim is made to have selected the strongest implementation from them. This
release uses original code; no source or databases from those ZIPs were copied.
Reference-source comparison and actual Gathercraft database inspection remain
outstanding. No gathering routes or navigation were added to Market.

## Optional Nexus contract

```lua
local market = _G.VoidMarkMarket
local api = market and market.PricingAPI
if api and api.version == 1 then
  local price = api.GetPrice(2447)
  -- price.status: current / stale / unavailable
  -- price.price is a current meaningful ask; historicalPrice stays separate.
  -- resalePrice exists only after local evidence gates pass.
  local quote, reason = api.GetAcquisitionCost(2447, 20)
  -- quote: totalCost, purchasedQuantity, surplus, availableQuantity,
  -- timestamp, confidence, source, tiers, requiresLiveCheck.
  local opportunities = api.GetCraftingOpportunities()
  local farming = api.GetFarmingComparison(2447, measuredUnitsPerHour)
end
```

Call after addon initialization; absent/unready prices are normal. Returned
tables do not alias SavedVariables. No remote price imports are trusted for
these valuations. Nexus should supply measured yield and own all routes,
navigation and farming execution. Farming figures do not deduct travel time,
repair costs or opportunity cost of the player's time.

Trusted optional integrations may register deterministic recipe records using
`market:RegisterRecipe(record)` and explicitly verified disenchant outcomes with
`market:RegisterDisenchantModel(itemID, model)`; these are developer interfaces,
not an import channel for arbitrary unverified market claims. Disenchant models
are session-only and must be re-registered. Eligibility remains an in-game check.
