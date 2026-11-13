## 1.23.10
- **Buy pages no longer time out on items you already looked at.** Forever sometimes refreshes a search of an item already searched this session without sending "results updated". The buy page (e.g. from Listings → See listings / buy after an undercut check) then waited, retried and failed with "Request timed out". It now reads the complete results after 3 seconds, like price checks already did. Buying stays safe: an item auction is bought by its auction ID (a gone auction just fails), and commodities get a fresh quote before you confirm.
- 297 regressions.

## 1.23.9
- Mail tracking (won mail, mailing between your characters) is only for **gear**: weapons and armor like boots, belts, cloaks. Stackables like leather and cloth aren't tracked through the mail.
- 296 regressions.

## 1.23.8 — mail tracking
- **"Auction won" mail records the buy.** Anything you buy, in Market or the normal AH window, lands in the Flip Ledger when its mail shows up. Market's own Buy Now is matched, not doubled. Won mail Market saw before this update is added once at login.
- **Mailing items between your characters.** Mail a flip to your bank and your main's Flip Ledger marks it "Mailed to Voidmark Bank" (no longer held there). When the bank opens that mail, it gets the buy with what your main paid, shown as "(from Voidmark Soulreaver)". When the bank sells it, the profit is real. Its cost isn't counted as gold the bank spent.
- 295 regressions.

## 1.23.7
- **Sale banners show the flip as a percentage** of what you paid: paid 2s 50c, profit 7s → "+7s flip  +280%". Losses show the same way ("-47%"). The chat line too.
- 293 regressions.

## 1.23.6
- Version numbers: 1.22.24–1.22.26 were released while 1.23.x (sniper) was already out; they are renumbered 1.23.4–1.23.6.
- **A full scan the server doesn't answer no longer blocks everything for 3 minutes.** Forever sometimes never answers a full scan ("no replicate response after 180s"). Until now Market held every search and price check behind it for those 3 minutes. After 10 seconds without an answer, the scan now keeps listening in the background and your searches go right through. If the server answers later, the scan completes normally. If it never does, it reports the same 180s timeout as before.
- 292 regressions.

## 1.23.5
- **The automatic bank scan waits while you shop.** A full scan holds the AH until the server answers, so a buy page opened just as it started sat on "Searching..." for 20+ seconds. The scan no longer starts while a buy page is open, or within 2 minutes of shopping, selling or checking listings.
- **Buy pages say what they're waiting for**, with a seconds count: "Waiting for the full scan to start (12s)", "Waiting for a search-term page", "Waiting for your auctions to load", "Waiting for the AH to answer (4s, try 2)" or "Waiting for the AH to accept a search".
- 291 regressions.

## 1.23.4
- **Bank sync no longer gets stuck ("sending 90%").** Prices saved while the PC clock was ahead had times in the future. The receiving character refused the page holding them and never confirmed it, so the bank resent it forever and the main's prices went stale ("last seen 9h ago").
  - Future times in synced pages are pulled back to now and accepted.
  - One unreadable row is skipped; the rest of its page applies and the transfer moves on.
  - At login, saved times that are ahead of now (prices, history, Flip Ledger, sync stamps) are pulled back to now in the background. Guards meant for the future ("...Until") are left alone.
- 290 regressions.

## 1.23.3
- **Full scan blocked for hours ("Next scan in 846m").** The last scan time was saved in the future, most likely while the PC clock was wrong (new PC). A future time is now ignored, so the 15-minute timer works again.
- The empty Hits view explains what the sniper looks for and that 0 hits is normal.
- 288 regressions.

## 1.23.2 — sniper settings without slash commands
- On the **Hits** view the bottom bar has three buttons instead of Flip Ledger / Export Results:
  - **Flag: 50% or less** — click, pick 30 / 40 / 50 / 60 / 70%.
  - **Min profit: 50s** — click, pick 10s / 25s / 50s / 1g / 2g / 5g.
  - **Sound: On/Off** — click to switch.
- Any other search brings Flip Ledger / Export Results back. Slash commands still work but aren't needed.
- 286 regressions.

## 1.23.1 — sniper false alarms
- **Far fewer false hits.** 1.23.0 compared listings only with the 30-day average. Forever prices are still falling, so whole markets (850 Fel Leather "at 23%") looked like misposts. The sniper now uses the **lower** of the 30-day average and the newest full scan (yours or Bank's, synced), and that scan must be under 6 hours old. No recent scan = the item never fires.
- The chime plays at most once every 15 seconds.
- The sniper's status stays on the Shopping status line; the top line shows the scan timer again.
- **Level box** now filters saved-price results too, not only live AH searches. Your own list items and snipe hits always show.
- Rows no longer show a blank name when the AH hasn't loaded an item's name yet.
- 285 regressions.

## 1.23.0 — mispost sniper
- **Snipe** (Shopping tab, top right, or `/vmm snipe`). While the AH is open it re-reads the whole Auction House again and again (one lowest price per item, the quick browse read, not the 15-minute full scan) and flags anything listed far under its own 30-day price: a misposted or fat-fingered listing.
  - A hit needs **both**: price at **50% of average or less**, and **50s or more** gain after the 5% AH cut. Change them with `/vmm snipe pct 40` and `/vmm snipe min 1g`.
  - Only items with real history for that exact suffix count. The all-suffixes estimate and brand-new items never fire, so a cheap suffix of an expensive item isn't a "mispost".
  - New hits chime, print in chat and show under **Hits**. Click one for the normal buy page (live listings, Buy Now, ledger, risk limits). Nothing is ever bought for you.
  - A hit that's no longer that cheap (someone bought it) is marked GONE and can alert again if it's reposted cheap.
  - The sniper pauses while you're on a buy page or a full scan is processing, and stops when the AH closes.
  - It saves nothing: misposts never become the market price, a daily low, or a synced price.
- `/vmm snipe sound` turns the chime off/on. `/vmm snipe hits` opens the list.
- 281 regressions.

## 1.22.23
- **Sale banners at login show the price.** Each session starts with an empty list of your auctions, and the banner only looked at the list saved from last time when there was no list at all. So right after logging in it never used the saved list ("price shows when the mail arrives"). It now checks this session's list, then the saved one.
- A listing already shown as SOLD can match its sale banner (it sold while you were online but the message came later).
- Opening the AH now loads your auctions automatically, as intended in 1.22.x. The same empty list stopped that too.
- The post-price and market-price fallbacks never use another suffix's price.
- 273 regressions.

## 1.22.22 — suffix sweep
Forever's item links leave out the suffix ("[Pagan Belt]"), while the AH sells each suffix as its own item. Everything that matches items now goes through one set of rules (exact AH key > full name > base name), instead of each screen guessing.
- **Scans keep a price per suffix.** Every suffix of an item used to land under one price. A scan now records each suffix's own lowest price; the shared entry is named after the base item and marked as mixed.
- **Tooltips** show the hovered suffix's own price, or "No price for this suffix yet". They never show a mixed price, or a synced price that can't be told apart.
- **Selling** uses the AH's own key for the exact item. Never-below, favourites, post history and what you paid are per suffix, and the price is the last scan price for that suffix.
- **Listings** show full names ("Pagan Belt of the Sorcerer"), taken from the AH.
- **Flip Ledger**: buys saved with only the base name get their full name once the AH is opened. What you paid, Last Bought / Last Sold and sale matching never take another suffix's buy. When an exact match exists, a buy saved without its suffix isn't used.
- **No more loose name matches.** "Silk" no longer matches "Silk Cloth", and "Heavy Leather" no longer matches "Heavy Leather Ball". Names match exactly, or as base name + " of ...".
- Post history is also saved under the auction's AH key, so sale banners find your post price for gear.
- 272 regressions.

## 1.22.21
- **Last Bought shows on gear you just bought.** Forever's purchase link only says "Greenweave Gloves", so the buy was saved without its suffix and never matched the tooltip ("Greenweave Gloves of the Sorcerer").
  - New buys are saved with the AH's full name.
  - Buys already saved with only the base name are matched by asking the AH what that exact item is called, so a different suffix of the same gloves still doesn't match.
- 269 regressions.

## 1.22.20
- **Listings: "See listings / buy".** Select one of your auctions (or double-click it) to open that exact item's buy page right on Listings: every other seller's listing with price and count, ready to buy out an undercut. Back returns to your auctions.
- **Undercut checks no longer reset to "Not checked".** Your auctions reload often (after posting, opening the AH, Refresh), and each reload wiped the results. They're now kept for 15 minutes per auction, and a check that finishes during a reload still lands.
- 268 regressions.

## 1.22.19
- Selecting an item on Selling fills the quantity with how many of *that suffix* you have. It counted both Pagan Belts (Intellect and Sorcerer) as 2, and the post failed with "Invalid price, duration, quantity or item variant".
- 267 regressions.

## 1.22.18
- **Different suffixes of one item are no longer mixed up.** Forever's item links leave out the suffix, so Pagan Belt of Intellect and Pagan Belt of the Sorcerer looked like the same item:
  - The sell list shows each with its real name (from the item's tooltip) as its own tile, and Max counts only that one.
  - A scan price saved under another suffix's name isn't used. The sell screen says "No scan price for this suffix yet", and the price comes from the live AH search, which already uses the exact item.
  - Tooltips show "No price for this suffix yet" instead of the other suffix's price.
  - Posting never picks the other suffix from your bags.
- 267 regressions.

## 1.22.17
- **Tooltip Last Bought matches on the item's full name.** Forever's tooltip title has the full name ("Greenweave Gloves of Healing") even when the item link doesn't. That name is now matched against the ledger, so a buy shows even if the AH and your bags number the suffix differently.
- `/vmm tipcheck` while hovering an item prints what the tooltip compares (title, link, key, ledger rows).
- Fixed `/vmm flipsync` erroring.
- 264 regressions.

## 1.22.16
- **Your bank toon now knows what your main paid (and the other way round).** Each account keeps its own ledger, so an item bought on one character and mailed to the other showed no "Last Bought". Buys now go to your synced partner in the background, using the same send budget as price syncing.
  - Used for the tooltip's Last Bought, "You paid" on the sell screen, the Paid column in Listings, and the never-sell-below-paid floor.
  - Partner buys never count in this account's Flip Ledger profit totals.
  - Your whole buy history goes over the first time the two connect. `/vmm flipsync` sends it again.
- 263 regressions.

## 1.22.15
- **Buy pages load faster.** Clicking an item no longer waits behind a background request that's already running (a search-term page, your auctions, a price check). That request is put back in line and the item's search goes out right away.
- **Chain buying no longer fails with "A search for this item is already running."** A second search for the same item now joins the one already running and gets the same results.
- If the server ignores a refresh of an item you already looked at, Market sends a new search after 5 seconds instead of waiting up to 45.
- 262 regressions.

## 1.22.14
- **Sale banners for herbs, leather and other stackables show a price.** Mageroyal and Thick Leather sold with "Price shows when the sale mail arrives":
  - Posting with Market now saves the post price at the moment you post (stack posts don't always send the event it waited for) and reloads your auctions a few seconds later.
  - If an item wasn't posted with Market, the banner shows the current market price, marked "About 1s 45c each (market price)".
- 261 regressions.

## 1.22.13
- **Fixed: "Last Bought"/"Last Sold" missing on tooltips.** Forever's item links carry only the base name ("Durable Belt") while the AH and sale mail use the full name ("Durable Belt of the Physician"), so buys recorded from mail never matched. Tooltips now match on item + suffix when both are known, otherwise on the base name + "of ...".
- **Listings has a Paid column:** what you paid for each listed item (purple), red when your price after the 5% cut doesn't cover it, "--" when there's no buy on record.
- 260 regressions.

## 1.22.12
- **Fixed: the AH's Sell slot and "Create Auction" button showing over Market's tabs.** Clicking or dragging a bag item switches the AH to its own Sell view behind Market's page, and its item slot drew on top. Market's tab pages now sit near the top of the AH's layer (frame level 8000, was +200). Blizzard's frames are still never hidden or changed, and Market's popups and windows stay on top.
- 259 regressions.

## 1.22.11
- **Test sound** button in Settings (and `/vmm testsound`): plays the sale sound and says in chat whether the chime played, whether the coin sound was used instead, and what in your sound settings would keep you from hearing it (all sound off, Master volume 0, "Sound in Background" off, Sale sound switched off, or quiet while the partner is online).
- 259 regressions.

## 1.22.10
- **Only one chime when both characters are online.** New Settings switch "Quiet when partner online": that character plays no sale sound while the synced character is online (banner and chat still show). On by default for Voidmark Bank, off elsewhere, so the main chimes for both its own sales and the bank's. When the bank is on alone, it chimes as usual.
- 258 regressions.

## 1.22.9
- **Sale chime:** sales now play your LockChime sound (Media\LockChime.ogg) instead of the coin sound. If the file can't play, the coin sound is used.
- **Settings:** "Sale message" (purple banner + chat line) and "Sale sound" (the chime) now switch on and off separately; turning the message off no longer silences the sound.
- New file: restart the game fully once (not just /reload) so WoW can find the sound.
- 257 regressions.

## 1.22.8
- **Sale banners show a price more often** (the Silk Cloth alert had none):
  - Your auctions now load a few seconds after the AH opens, so Listings doesn't have to be opened first.
  - The last loaded list of your auctions is saved, so prices are still known after a /reload or a fresh login.
  - Otherwise the price you last posted that item at with Market is used. For stacks (cloth, herbs) that can sell in part, the banner says "Sold at 1s 20c each (your last post)".
- 256 regressions.

## 1.22.7
- **Purple sale banner** (VoidMark Taunt style) replaces the yellow raid-warning text: dark panel with a purple border, "VOIDMARK BANK SOLD" (or "SOLD") label, the item, "Sold 35s · you get 33s 25c · paid 22s", and a big green "+11s 25c flip" (red "loss" when below what you paid; no profit line without a buy record). Middle of the screen, fades after 6 seconds, up to 4 stack. Drag one to move them; the position is saved. Still printed in chat, with the coin sound.
- 255 regressions.

## 1.22.6
- **Fixed: no sale alert when an auction sold.** Forever's AH reports "A buyer has been found..." and "You won an auction..." through its own notification event (AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION), which the chat frame prints itself; no system chat message is ever sent, so 1.22 never saw them. Market now listens to that event:
  - Sales alert (sound, screen, chat) and are sent to the synced character. The notification names the exact auction, so the alert uses that auction's price.
  - Wins on the normal AH are recorded in the Flip Ledger again.
  - If a chat message for the same sale also arrives, it isn't counted twice.
- 254 regressions.

## 1.22.5
- **Fixed: the AH's own "Auctions" tab showing over the VOIDMARK MARKET title** when a Market tab is open. Market's page now sits well above the native Auctions view (frame level +200, was +30). Blizzard's frames are not hidden or changed, so bag items keep working while the AH is open.
- 253 regressions.

## 1.22.4
- **Fixed: the sending character being disconnected from the server.** 1.21's fast sync gave each of its 4 lanes its own send budget, so the bank sent up to 4x the addon messages per second, and the server disconnects a character that floods addon messages. All lanes now share the old single budget (1200 bytes/second, 8 pages in flight), the same rate that ran fine before 1.21. Packed messages are kept, so sync is still faster than 1.20 without sending more. A refused (throttled) send now pauses all sending briefly.
- 253 regressions.

## 1.22.3
- **Sync reconnects within 30 seconds.** When the partner isn't online yet, each character now knocks at most every 30 seconds (was up to 60), and a "player not found" pause is 30 seconds (was 60). Once connected, the 20-second heartbeat keeps the link up, and the link is dropped and re-probed after 65 seconds of silence. Either character can be the one that's always on; the other finds it within half a minute of logging in.
- 253 regressions.

## 1.22.2
- **Clearer tooltip age.** When a full scan (yours or the synced character's) ran after an item's price was last seen, the item isn't on the AH right now. The Auction line now says "(none listed now, last seen 14h ago)" instead of just "(14h old)", so an old price no longer looks like a stale scan.
- 253 regressions.

## 1.22.1
- **Settings has the flipping switches:** Sale alerts, Coin sound, Send to partner, Never sell below what I paid (hover each for what it does). They match the `/vmm salealerts`, `/vmm salesound` and `/vmm paidfloor` commands.
- 252 regressions.

## 1.22.0
- **Sale alerts.** The moment an auction sells (AH open or not): a coin sound, a message in the middle of the screen and in chat:
  "Sold Lupine Vest of Agility for 49s - you get 46s 55c | flipped for +32s 55c (paid 14s)".
  - The price comes from your listing (Listings), what you paid from the Flip Ledger. If the listing isn't known, it says the price shows when the mail arrives.
  - **Sent to your other character** over the sync link, so the bank selling shows on your main ("Voidmark Bank: Sold ..."). Needs both on 1.22.
  - `/vmm salealerts off` turns them off; `/vmm salesound off` keeps the message without the sound.
- 251 regressions.

## 1.21.0
- **Faster bank-to-main sync** (both characters need 1.21; until then the old format is used automatically):
  - Messages go out over 4 channels ("lanes") instead of 1. The game limits how fast each channel can send, so more channels means more data per second. If one is throttled, the others keep going.
  - Smaller messages: the realm/faction name is sent as a 5-character code, and prices and timestamps are packed, so more prices fit in each message.
  - Up to 8 messages in flight per lane (32 total instead of 8). The receiver puts pages back in order if they arrive out of order.
  - VoidMark > Sync shows "Sync mode: fast, 4 lanes" once both sides are on 1.21.
- 250 regressions.

## 1.20.3
- **Flip Ledger now includes what happened before it existed.** On first load it rebuilds buys and sales from Market's older log: confirmed Market buys, "You won" invoices (buys from anywhere) and "Auction successful" invoices (sales), matched oldest buy first. Rows already in the Flip Ledger are never added twice. Chat says how many were added. `/vmm flipsrebuild` runs it again.
- 247 regressions.

## 1.20.2
- **Faster buy pages:** while you're on an item's buy page, the background search-term pages wait, so the item's listing search goes out next instead of queuing behind them. They carry on when you go back.
- **Faster list searches:** `/vmm flipstarter` now adds the terms as greens only (`green cloth: magic`, ...). The AH sends far fewer result pages. Run `/vmm flipstarter` again to switch; your own terms are kept.
- The Flip Ledger button no longer shows through the buy page.
- 246 regressions.

## 1.20.1
- **Flip history is never thrown away.** The Flip Ledger keeps 5000 rows in detail (was 1500). Past that, the oldest fully sold rows are folded into per-item totals that still count in By item, By suffix and all-time totals. Items you still hold are never removed.
- **Failed scans say why** on the status line (for example "no replicate response after 180s"), and that your last good prices are still in use.
- Updates never touch your saved data: it lives in WTF\Account\...\SavedVariables\VoidMarkMarket.lua (not the addon folder), and the Warpath updater refuses to write there.
- 245 regressions.

## 1.20.0
- **Flip Ledger is its own AH tab** (between Listings and VoidMark). The Flip Ledger button on Shopping and `/vmm flips` open that tab while the AH is open; away from the AH, `/vmm flips` still opens it as a window.
- 243 regressions.

## 1.19.0
- **Item tooltips show "Last Bought" and "Last Sold"** (per item, always on), like the flipping addon your friend uses. Hold Ctrl for when, which character bought it, what it sold for after the cut, and averages if you've traded it more than once.
- **Never sell below what you paid.** For an item you bought and still hold, the suggested post price never goes under what you paid plus the 5% AH cut. Selling says "held at what you paid + AH cut" when that kicks in. A higher "Never below" you set still wins. Turn it off with `/vmm paidfloor off`.
- **Flips to list first.** On Selling, items you bought and haven't sold are grouped at the top under "Flips to list"; Skip walks through them. (The game needs one click per post, so this is as close to one-click as an addon can get.)
- **"You paid" moved into the Selling info line** (it overlapped the Post button).
- **`/vmm check`**: hover an item (or type `/vmm check ` and Shift-click it) to print how the game labels it, whether Market has saved prices for it, its daily lows, its Vs Avg reference and its ledger buys/sales.
- Daily price history is capped (6000 items, 3000 base items); the items not seen for longest are dropped first.
- 242 regressions.

## 1.18.0
Second pass over Auctionator 345 (reference only; no Auctionator code used).
- **Import takes Azmork's whole Auctionator list, filters included.** Auctionator saves each term as `text;category;...;minLevel;maxLevel;...;maxPrice;quality`. Market used to keep only the word; now it converts category (armor type and slot), required level, max price and quality: `agility;Armor/Leather;...;0.5` becomes `leather: agility max 50s`. A list named "shopping" goes into your main Shopping list.
- **Quality in a term:** `green cloth: magic`, `blue: ...` (grey, white, green, blue, epic). The AH is asked for that quality only, so searches return fewer pages and finish faster.
- **Exact name in quotes:** `"Lupine Vest of Agility"` only matches that name (Auctionator's exact search).
- **An unconfirmed item buy no longer stops you buying** (Auctionator never blocks). You get a reminder with I got it / Didn't get it; its gold stays reserved until settled. A buy still in flight and unconfirmed commodity buys still block, so nothing gets bought twice.
- Search terms can be up to 60 characters.
- 240 regressions.

## 1.17.0
Checked against Auctionator 345 (reference only; no Auctionator code used).
- **Vs Avg fills in much sooner.** Like Auctionator's price history, every live search (search terms, typed searches, list searches) now records the day's lowest price, kept 30 days. Vs Avg uses those days plus full-scan history for the exact variant.
- **When a suffix has no history yet, Vs Avg compares with the same item across all suffixes and shows "~"** (e.g. ~45%). That is how Auctionator prices gear on Forever (it ignores the suffix), so treat "~" as a rough guide.
- A failed AH search now ends right away instead of waiting for a timeout; searches read up to 40 pages.
- Armor-slot search terms use the game's own slot IDs when available.
- 237 regressions.

## 1.16.0
- **Flip Ledger, built out for learning what flips:**
  - **Every buy:** item, what you paid, when, what you have it listed at, what it sold for (after the AH cut), when, how many days it took, profit, and status (Holding / Listed / Sold / expired xN).
  - **By item** and **By suffix** summaries: bought, sold, average paid, average sold, total profit, ROI, average days to sell, still holding, times expired. Best profit first, so you can see which items and suffixes make money and which don't.
  - **All time / 7 days / Today**, sortable columns (click a header), **Export CSV**.
  - Totals: spent, sold for, profit, deposits lost, holding (what you paid), and what your listed items bring in if they all sell.
- **Buys made outside Market are recorded too** (normal AH Browse, other addons): from the bid you placed and the "You won an auction" message.
- **Listed at** is filled in from your auctions whenever Listings refreshes.
- **Expired auctions** ("Auction expired" mail) are counted, and the lost deposit comes out of that item's profit.
- **Selling shows "You paid ..."** for the item you select, so you can price it for a profit.
- 235 regressions.

## 1.15.4
- **Hold Ctrl over an item to see what you paid.** Item tooltips (bags, AH, mail, anywhere) show "Hold Ctrl: what you paid" for items you've bought; holding Ctrl shows the last price you paid, when, what it sold for if it sold, and your average if you bought it more than once. The tooltip updates as you press or release Ctrl.
- 232 regressions.

## 1.15.3
- **Fixed: Shopping tooltips showing "Items in this group may vary" with no stats.** Result rows now use the real item link from your saved scans (or build one for fixed-stat suffixes), so the tooltip shows the suffix stats and required level.
- **Vs Avg finds your scan history more often.** Live searches and full scans can label the same gear differently (with or without item level); results now match saved prices by item + suffix.
- 231 regressions.

## 1.15.2
- **Fixed: text overlap on Listings.** The selected auction's undercut verdict ran into the Listed/Inbound gold line. It now shows in the header above the list, on its own.
- Undercut verdicts are in plain words ("Nobody else is selling this. Keep it.", "Undercut 12% (cheapest now 30s). Small gap: keep it.").
- 230 regressions.

## 1.15.1
- **Fixed: Lvl column stuck on "--".** Items the game hadn't loaded yet never showed a level, because nothing asked for them or redrew when they arrived. Visible rows now ask the game to load the item (once) and the list redraws when it arrives.
- 229 regressions.

## 1.15.0
- **Flip Ledger** (Shopping > **Flip Ledger**, or `/vmm flips`): every item you buy, what you paid, what it sold for (after the AH cut), profit, and whether you're still holding it.
  - Buys are recorded when confirmed. Sales are read from "Auction successful" mail when you open your mailbox, matched to the oldest unsold buy of the same item. Sales with no buy record are listed too.
  - Totals: spent, sold for, profit on sold items, and what you're holding (count and cost). Filter All / Holding / Sold. Right-click a row to remove a mistake.
  - Starts empty: only buys from now on are tracked.
- 228 regressions.

## 1.14.6
- **Fixed: buying stuck on "A purchase result is still unknown".** If the AH closed (or the result never arrived) after Buy Now, Market blocked every later purchase until you settled it in the Ledger.
  - The "You won an auction for ..." chat message now confirms it automatically.
  - Shopping's buy view shows **I got it** / **Didn't get it** to settle it right there.
- 227 regressions.

## 1.14.5
- **Fixed: item tooltips on Shopping.** Hovering the item in the buy view showed the base item ("Greenweave Sandals", no "of Healing" stats) and opened upward over the search bar. Tooltips now show the exact variant you're buying (auction link, or the item's suffix), and the buy-view tooltip opens below the icon. Result rows show the suffix too.
- 226 regressions.

## 1.14.4
- **Lvl column on Shopping results:** the item's required level (shows -- until the game has loaded the item). Click the header to sort by level.
- 225 regressions.

## 1.14.3
- **Fixed: higher-level items missing from searches.** The Auction House sends search results a page at a time and Market only read the first page, which fills up with cheap low-level greens. Search terms and typed searches now keep asking for more pages (up to 20) before moving on.
- 224 regressions.

## 1.14.2
- **Search terms take options, like Auctionator's extended search:** `[armor] [slot]: [text] [max 75s] [lvl 15+ | lvl 15-30]`.
  - `leather: agility max 50s`, `cloth: intellect lvl 15+`, `mail head: max 75s` (no text = every mail helm under 75s).
  - Slots: head, shoulder, chest, waist/belt, legs, feet/boots, wrist/bracers, hands/gloves, back/cloak.
  - A term's own max and level win over `/vmm flipmax` and the Level boxes.
- **`/vmm flipstarter` now adds Azmork's list** (cloth magic / sorcerer / intellect 15+ / healing and physician under 75s, leather agility under 50s / monkey / tiger / helms under 75s, mail bear / strength / helms under 75s) and removes the 1.14.0 starter terms. Your own terms stay.
- 223 regressions.

## 1.14.1
- **Level range on Shopping:** Level [min] - [max] boxes next to Add to List. Applies to every Shopping search (search terms and typed names). Leave a box blank for no limit. The range shows under the results.
- Term results show the item's name instead of "Item 14117" once the game has loaded it.
- 222 regressions.

## 1.14.0
- **Flipping: search terms in shopping lists.** A list can now hold search text like "of the Monkey" as well as items. Type it in the Search Term box and click **Add to List** (or copy a recent search to the list). Opening the list searches its items and every term, and merges the results.
- **Armor type in a term:** "leather: of the Monkey", "cloth: of Healing", "mail: of the Bear" (cloth, leather, mail, plate) only show that armor type.
- **Starter list:** `/vmm flipstarter` adds 11 terms to your main Shopping list: leather of Agility / Monkey / Tiger, cloth of Healing / Intellect / Sorcerer / Physician / Magic, mail of Bear / Tiger / Strength.
- **Max buy price:** `/vmm flipmax 15` hides term results above 15 silver (`/vmm flipmax 0` turns it off).
- **Vs Avg column** on Shopping results: the lowest price as a % of that exact item's 30-day average (each random suffix is its own price; needs at least 2 scans). Green = a deal, at or under 60% by default (`/vmm deal 50` to change). Click the header to sort deals first.
- **Import** also accepts an Auctionator list export (`Name^term^term`).
- Search terms stay on the character that made them (items still sync to your other account).
- 221 regressions (8 new).

## 1.13.2
- **Cancelling is now called Listings** (it's your auctions overview: status, undercuts, inbound gold). Saved settings are unchanged.
- **Your auctions load faster:** opening Listings or pressing Refresh now goes ahead of list and name searches in the Auction House queue (only a purchase in progress goes first), and reading the results is treated as something you're waiting on.
- **Bank sync is the lowest priority:** its background work only uses time left over after everything else, and catches up once the AH work is done.
- Note: if a full price scan is already downloading, the AH answers that first; Listings loads right after.
- 213 regressions.

## 1.13.1
- **Cancelling: inbound gold tally.** Under the list: **Inbound** = gold from sold auctions on its way by mail (count and when the next mail arrives), and **Listed** = what your active auctions bring in if they all sell. Both after the AH cut (5% by default).
- 212 regressions.

## 1.13.0
- **Shopping tab now matches Auctionator's layout and behavior** (rebuilt in Market's own code, VoidMark colors):
  - Top bar: Search Term box with a clear button, **Search** (turns into **Cancel** while searching), **More...** and **Add to List**. An empty box with a list open searches the whole list.
  - Left: **Shopping Lists** / **Recent Searches** tabs. Lists open like folders (+/−) to show their items and search the whole list; click an item to search just that item. Lists have search / rename / delete icons, items have remove, recent searches have delete / copy-to-list. Right-click collapses. **New List**, **Import**, **Export** underneath. The main Shopping list can't be renamed or deleted.
  - Results: sortable **Price / Name / Available** headers, scrolling instead of pages. Left-click opens the buy view, right-click shows price history, shift-click copies the name into the search box. **Export Results** gives CSV.
  - **More...**: exact name, max price and min available filters (a plain Search clears them).
- Lists still hold items (not search text) and still sync between your accounts.
- 211 regressions (8 new).

## 1.12.2
- **Fixed: wrong "Auction xN" on tooltips.** Hovering a mail attachment (or any button numbered like a bag slot) showed the stack size of whatever sat in that backpack slot, e.g. "Auction x20" on 2 Rosecap. Mail attachments now use their own count, and a bag slot is only trusted when it holds the hovered item.
- 203 regressions.

## 1.12.1
- **Fixed: prices showing old after a scan.** A full scan has two parts: reading every auction (needs the Auction House open), then saving prices item by item. Closing the Auction House during the second part stopped it, so some items kept yesterday's price and age ("1d old") even though you scanned today. Saving now finishes after the Auction House closes; only the reading part still needs it open.
- 202 regressions.

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
