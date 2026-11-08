## 1.9.0
Auctionator-style screens (own code and VoidMark styling, Forever rules).
- **Selling:** bag items as icon tiles grouped by type, Favourites first (right-click a tile). Header with item, Quantity + Max, gold/silver/copper price boxes, 2h/8h/24h, Deposit and Total, Post and Skip. A "Never below" minimum per item. The listings table shows every live price with your own marked; click a row to price just under it (or match your own). Sub-tabs: Current prices, Price history, Your history (last 20 posts per item).
- **Shopping:** lists on the left with a search icon each, a Recent searches tab (last 20), New list and Import / Export. Search box with Search, Add to list and Remove. Results show Price, Name, Available and how fresh the price is. Double-click or Buy... to buy.
- **Tooltip:** Auction line plus the stack total; old prices are grey with their age. The Vendor line is off by default because Forever already shows Sell Price. `/vmm version` prints the loaded version and sync partner.
- Posting queue moved to the VoidMark tab > Tools. Full scan stays on the VoidMark tab (Scanning), like Auctionator.
- 164 regressions.

## 1.8.0
Auctionator 342 used as the behavior reference (independent code; nothing copied).
- **Shopping:** opening a shopping list searches every item on it live (also **Search this list**). Rows show the live lowest price, how many are up, or **None listed**. Name search now shows the available quantity.
- **Live prices:** every complete live search (shopping, selling checks, undercut checks, name search) records the lowest competitor price. Tooltips and lists use it when it is newer than your last scan, labelled **Live search**. Scan history and models are not changed. Kept 7 days, capped at 5,000 items.
- **Selling:** clicking a bag item checks the live price right away and fills **lowest price minus 1 copper** (Settings > *Selling undercut (copper)*; 0 = match). Never below your saved minimum. Commodities default to everything in your bags. The 2h/8h/24h choice is remembered. After a post, the next bag item is selected and checked.
- **Cancelling:** **CHECK UNDERCUTS** searches each item once and marks listings UNDERCUT, LOWEST, NO COMPETITION or SOLD. **CANCEL NEXT UNDERCUT...** opens the confirm for the next undercut listing, one cancel per click. Time left reads as hours/minutes. Cancelled rows drop off the list.
- 158 regressions (9 new).

## 1.7.1
- Auctionator-style tabs: **Shopping**, **Selling**, **Cancelling** and **VoidMark** on the Auction House tab row (replacing 1.7.0's single tab). Each trading tab opens its own screen with no section buttons; sub-screens such as Buy Item show a **< Back** button.
- The **VoidMark** tab holds Scanning, History, Vendor, Crafting, Settings and Tools, and reopens the last one used.
- With Auctionator also loaded, the trading tabs read **VM Shopping**, **VM Selling** and **VM Cancelling** so the two sets are distinguishable.

## 1.7.0
- Auction House: one **VoidMark** tab replaces the five separate tabs that crowded or clipped the tab row (worst with Auctionator). The tab reopens the last section you used.
- Market navigation: Shopping, Selling, Canceling, Scanning, History, Vendor, Crafting, Settings, Tools.
- Drag any empty part of the Auction House (native tabs included) to move the whole window. Position and scale are saved and restored each time the AH opens; MoveAny keeps control when it is installed. Settings > Reset Window resets the AH layout while docked.
- The docked Market layout re-fits when the AH is resized or rescaled, so controls are not clipped.
- Tooltips: compact per-unit price, stack total for hovered bag stacks, CURRENT vs STALE label with source and age, and a "No AH price yet" line for auctionable items without data (bind-on-pickup and quest items stay silent).
- Bank-to-main catch-up: trusted prices older than the 2-hour freshness window (for example, scanned before pairing) are now offered to the partner, labelled by age, and never replace a newer observation. Existing journals re-seed once after updating.
- Sync no longer stalls permanently on a revision too large for one addon message; throttled sends retry after 1.5 s instead of 4 s.
- Removed leftover button names (SNIPER, BANKER, REVALIDATE, FULL SCAN) from help text. Verified no Safe Mode code or text remains.
- Tests run on stock Lua 5.1 without lupa. 149 regressions.

## 1.6.0
- Replaced twelve main tabs with Shopping, Selling, Canceling, Vendor Deals, Crafting, and Tools.
- Added item-name search with Enter, saved-list sidebar, readable price columns, and contextual empty states.
- Moved detailed scan reports into Diagnostics; simplified scan and connection status.
- Fixed sharing across spaced/normalized names for the same realm and faction.
- Included fractional per-unit stack prices in the shared price feed, rounded up to integer copper.
- Announced scan metadata after publication completes; sped up acknowledged price sharing.
- Reconnect now reseeds locally available prices without resetting financial records.

## 1.5.8 - Automatic account sync dashboard
- Add SYNC tab, automatic named pairing, automatic eligible bank-character AH scans,
  reconnect/full replay, peer scan metadata, persisted completion diagnostics.
- Refresh Browse after incoming price pages; show observation timestamps in Browse
  details and tooltips, with explicit synced/stale labels.
- Preserve saved data, throttled resumable deltas, trade gates, and offline backoff.
- Add pairing/off persistence, automatic scan guards, and sync dashboard regressions.

## 1.5.0 — Forever Live

Remove Safe Mode. Add confirmed manual shopping, posting and cancellation, named shopping lists, passive variant-specific price tooltips, and incremental paired-account sharing. Retain schema 1, account-local finances, old clipboard imports, crafting and the existing intelligence dashboards.

# Changelog

## 1.4.0-beta â€” 2026-10-30

- Add whole-stack depth pricing, own-listing exclusion, outlier filtering and
  fresh-generation stock invalidation without replacing the existing scanner.
- Add deterministic recipe capture, crafting chains, replacement/cash costing,
  sale scenarios, buy-versus-make comparison and risk-limited opportunity ranking.
- Add Crafting Intelligence, detailed calculations and shared-inventory project
  shopping lists to the existing purple terminal.
- Add optional PricingAPI v1 for Nexus, farming comparisons using supplied yields,
  and a validated optional disenchant-distribution interface.
- Preserve existing data and Safe Mode; add 24 regressions (121 total).
- Document unverified Forever behavior and inaccessible reference ZIPs in
  RELEASE_1.4.md. No third-party source or databases copied in this release.

Earlier release history remains in RELEASE_1.3.1.md, RELEASE_1.3.md and HARDENING.md.
