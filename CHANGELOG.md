## 1.12.0
- **Removed the Flips tab.** The Auction House tabs are now Shopping, Selling, Cancelling and VoidMark. Saved scans, prices and settings are untouched; the old flip settings stay in your saved file unused. Flip opportunities under VoidMark > Tools are unchanged.
- 201 regressions (the four Flips-screen tests were removed with the screen).

## 1.11.6
- **Bank sharing works with either Forever name form.** Forever can report a character as "Voidmark-Bank" (surname where a realm normally goes) instead of "Voidmark Bank". Market now accepts the partner in either form, pairs from "Voidmark-Bank", and while the partner has not answered it alternates "Voidmark Bank" and "Voidmark-Bank" when whispering, then keeps the one that gets through.
- **Your own full name is read even without NameUtil.** The surname is taken from the second UnitName value. Before, only "Voidmark" was read in that case, so automatic pairing and the automatic bank scan (which only runs on Voidmark Bank) never started.
- 205 regressions.

## 1.11.5
- **Fixed "VoidMarkMarket has been blocked from an action only available to the Blizzard UI" when using a bag item.** Clicking a VoidMark tab on the Auction House (or closing it with X) changed the Auction House's own display mode from addon code. Blizzard's bag-click code reads that value, so the next item you used from your bags was blocked. VoidMark tabs now sit on top of the Blizzard content without touching its state.
- 205 regressions.

## 1.11.4
- **Faster full-scan processing.** Trade goods, consumables and other non-gear items no longer read and parse an item link for every auction (once per item instead), and gear variants are resolved once per variant instead of once per auction. In a 132k-auction test that is about 65% fewer link reads and 75% fewer item-level look-ups, with identical results.
- **Selling: no more "Bag slot changed, locked or bound; select it again".** If the bag list is out of date (item moved, stacked, looted or posted), Market finds the item in its new slot and checks the price straight away, and the list refreshes. A slot that is only locked for a moment after posting is retried every 0.2 s instead of 0.5 s.
- **Price checks are not held up by background work.** The bag list, price-check results and searches run before scan/model/sync jobs each frame, and background jobs take turns.
- 205 regressions.

## 1.11.3
- **Cleaner Shift disenchant tooltip:** one value per material (no "each" prices or "old price" on every line), "Disenchant" total, and "Best Auction +23s 93c". Red Vendor when disenchanting is within 10% of vendor.
- Prices only count as old after a day (was 2 hours); when they are, the age shows once on the "Disenchants into" line. Setting `deMaxAge`.
- 202 regressions.

## 1.11.2
- **Disenchant tooltip is Shift-only** (no clutter otherwise). Hold Shift over gear: "Disenchants into:" each material with its chance, amount and its expected value at current AH prices (unit price in grey), then **Disenchant value** and **Best**. The tooltip redraws when you press/release Shift.
- **Within 10% of vendor defaults to Vendor:** if disenchanting pays no more than vendor +10%, Best says **Vendor** in red and the disenchant value is red. Same in the bag check window. (Setting `deVendorMargin`, default 0.10.)
- 202 regressions.

## 1.11.1
- **Disenchant window reads the whole VoidMark database:** new **AH items** tab (or `/vmm de ah`) goes through every scanned green/blue/purple weapon and armor in VoidMark's market data and shows Buy price, Vendor, Disenchant and Profit (disenchant value after AH cut minus the stored buy price), most profitable first. **My bags** tab is the old view.
- Items whose data isn't loaded yet are requested and counted ("press Refresh").
- 201 regressions.

## 1.11.0
Disenchant or vendor? (disenchant side of CraftShuffle, built into Market.)
- **Tooltip:** on green, blue and purple weapons and armor, a **Disenchant** line (average value of the materials on the AH, after the AH cut) and a **Best** line: Disenchant, Vendor or Auction, and by how much. Hold **Shift** to see the materials, chances and prices. `/vmm de tooltip` turns it off/on.
- **Bag check:** Tools > *Disenchant or vendor?* (or `/vmm de`) lists every disenchantable item in your bags with Vendor / Auction / Disenchant / Best, best first, and how much more you get by disenchanting.
- Yield tables from CraftShuffle 0.2.4 by Vystery (MIT), including the Forever change for green weapons ilvl 21-30 (Greater Magic Essence). Wands that can't be disenchanted are excluded.
- **Learns from your casts:** each of your disenchants is recorded (account-wide) and blended into the estimate for that quality/level band, so numbers move toward real Forever results.
- Prices come from your scans/searches and bank sync; old prices are greyed, missing material prices show "+?".
- CraftProfit's crafting features are not ported; Market already has Crafting.
- 200 regressions.

## 1.10.0
Auctionator-style buying in Shopping.
- **Click a Shopping result to open its buy view**, laid out like Auctionator's (VoidMark colours): Back, item icon and name, Refresh; Quantity, Unit price, Total price and Buy Now on the left; the live price tiers (Buyout price / Available) on the right.
- **Commodities:** type a quantity (Max fills everything listed) or click a price tier to buy every tier up to it. Unit and total prices add up across tiers like Auctionator.
- **Items:** listings are shown cheapest per item first; click one (or double-click) and Buy Now. "Paying X for N x Item?" is asked before every bid.
- **Chain buying:** after each purchase the listing refreshes and your quantity stays, so you can press Buy Now again straight away.
- **Warnings like Auctionator:** "CAREFUL - the price varies a lot" when the dearest unit is 50%+ above the cheapest; "The price has increased!" on the confirmation when the server quote is higher than shown (you choose; it is no longer silently rejected); final "Confirm purchase of N x Item for X? (Y each)". Not enough gold, your Settings limits and the commodity wait after a cancelled quote are shown in plain words under Buy Now.
- Every purchase still goes through the normal VoidMark path: spend limits, pending reservations and the ledger. Confirm a commodity quote within 15 seconds.
- 195 regressions.

## 1.9.13
Less memory.
- **Price history uses about 60% less memory.** Each item keeps its last 30 scans of history, and every entry used to be a full ~20-field snapshot (about 1.3 KB). History now keeps only the 6 fields Market actually reads (time, median, fair-value depth, quantity, lowest price, listings); the full snapshot is kept once, for the latest scan. Measured on 5,000 items after 32 scans: 221 MB -> 90 MB of addon memory. The SavedVariables file and login/logout time shrink too.
- History saved by older versions is converted once, in the background, the first time you log in. No prices or history points are lost.

## 1.9.12
Faster full scans.
- **Processing a full scan is several times faster.** Market used to handle a fixed small number of rows per frame (140 auctions, then only 12 items per frame while modelling), so a scan of ~25,000 auctions took about 1,000 frames (17 s at 60 fps, 34 s at 30 fps) even though the actual work is under 1 second. It now works to a time budget instead: 12 ms per frame while a scan is running at the Auction House (out of combat), back to 4 ms otherwise. The same scan now processes in about 70 frames (~1-2 s).
- `/vmm scanspeed fast|normal|smooth` (12 / 7 / 4 ms per frame while scanning). Default fast. Use smooth if you see a frame-rate dip at the AH.
- Items the client has not loaded yet are requested immediately, and retried every 0.25 s instead of 0.5 s, so the "Loading item data" step finishes sooner.
- Your character name is read once per scan instead of once per auction.
- After the scan, sharing to the bank partner and the gold-making list also rebuild faster.
- The finished scan now says where the time went, e.g. `Scan complete: 24,512 auctions, 4,980 items | server 18s | processing 1.4s`. The server part is the Auction House sending its data and is the same for every addon.

## 1.9.6
Bank sync status fix from in-game testing.
- **"Bank sync: waiting for partner" now clears as soon as the characters connect, on every screen.** The header line was only redrawn on a full window refresh, so Selling, Buy and other views could keep showing "waiting" long after the link was up (the Bank sync tools page refreshed every second, which is why it looked instant there). It now updates once a second on every view, and also switches back when the partner goes quiet.
- **Faster reconnect when the partner logs in later.** Unanswered probes now retry at most every 60 seconds (was up to 5 minutes), the quiet "partner offline" wait is 1 minute (was 5), and Market probes again right after a loading screen or a friend-list change.

## 1.9.5
Selling fixes from in-game testing.
- **Posts everything in your bags, not one stack.** Quantity and Max now use every unit of the item across your bags (e.g. 3 x 20 Linen = 60), the same way Auctionator does; non-stacking items become several auctions in one post. Previously non-commodity items were capped at the first stack. An old saved stack size (from the removed "save stack" box) no longer limits it. Typing a quantity keeps it.
- **No more "Bag slot changed, locked or bound" right after a post.** Market waits for the bags to update, selects the next item, then checks its price. A slot that is still locked is retried quietly.
- **Closing the AH during a price check** no longer leaves "Checking live price..." on screen.
- 172 regressions.

## 1.9.4
Low-FPS fix.
- **Item-name lookups** (1.9.0) asked the game for 100 items a second in the background, all the time. Each one makes the game and other addons do work, and each also re-priced your whole bag list. Now names load only while the Shopping screen is open and you're out of combat, 5 every half second, each item once per session.
- **Bag pricing** re-ran with the window closed whenever item data loaded, if Selling was the last screen. It now runs only while Selling is on screen.
- **Crafting** rebuilt every recipe on every bag change (looting, gathering). It now waits until a crafting screen is opened.
- **`/vmm perf`** measures VoidMark Market's CPU use for 10 seconds and prints the busiest parts.
- 171 regressions.

## 1.9.3
- **Live-search prices sync too.** A price seen in a live search (shopping, selling check, undercut check, name search) is sent to the partner like a scan price, without an estimate, so the partner's history and its age are unchanged. Unchanged prices repeat at most every 30 minutes. Settings key `shareLivePrices=false` turns it off.
- **Optional one-click posting.** Selling has an "Ask before posting" box (ticked by default). Untick it and Post posts straight away, like Auctionator; the slot, quantity, price-check and deposit checks still run.
- 170 regressions.

## 1.9.2
Faster bank-to-main sync.
- The bank used to send one page (about 8 prices) and wait for the main's reply before the next. It now keeps up to 8 pages in flight, paced to about 1.2 KB/s (burst 3 KB) to stay clear of chat disconnects. A lost page is resent from the last confirmed point; a throttled send waits 1.5 s and keeps its place. The main's side is unchanged, so no data format changed.
- An unchanged price is re-stamped at most every 30 minutes instead of after every scan. Repeat scans send far fewer messages; prices on the main can show up to 30 minutes older than the bank's last scan (still well inside the 2-hour fresh window).
- The main no longer rebuilds Shopping results for every page received; it refreshes once a second at most.
- 169 regressions.

## 1.9.1
Review fixes.
- **Post no longer fails after 15 seconds.** A checked price stays valid for a minute; after that, Post re-checks the live price (your typed price is kept) and asks you to click Post again.
- **"Never below" works on items this account hasn't scanned** (common on the receiving account).
- **Cancelling:** auctions of items you haven't scanned show their real name, icon and tooltip instead of "Item 12345".
- **Name lookup for synced prices** no longer walks the price table while sync is writing to it (that could stop the lookup or throw errors mid-sync), and only learns names for synced items.
- 168 regressions.

## 1.9.0
Auctionator-style screens (own code and VoidMark styling, Forever rules).
- **Selling:** bag items as icon tiles grouped by type, Favourites first (right-click a tile). Header with item, Quantity + Max, gold/silver/copper price boxes, 2h/8h/24h, Deposit and Total, Post and Skip. A "Never below" minimum per item. The listings table shows every live price with your own marked; click a row to price just under it (or match your own). Sub-tabs: Current prices, Price history, Your history (last 20 posts per item).
- **Shopping:** lists on the left with a search icon each, a Recent searches tab (last 20), New list and Import / Export. Search box with Search, Add to list and Remove. Results show Price, Name, Available and how fresh the price is. Double-click or Buy... to buy.
- **Tooltip:** Auction line plus the stack total; old prices are grey with their age. The Vendor line is off by default because Forever already shows Sell Price. `/vmm version` prints the loaded version and sync partner.
- **Cancelling:** rebuilt in the same style: item icons, undercut listings sorted to the top, coin prices, a summary line (undercut / lowest / not checked) and buttons that only light up when they can be used. Click a row to check it live.
- Shopping lists scroll with the mouse wheel when you have more than 16.
- Prices synced from the other account are now searchable by name: names the client doesn't know yet are fetched in the background and remembered. A search with no saved match says so.
- Money shows coin icons instead of 0g 1s 0c text.
- Posting queue moved to the VoidMark tab > Tools. Full scan stays on the VoidMark tab (Scanning), like Auctionator.
- 167 regressions.

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
