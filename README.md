# VoidMark Market 1.7 — WoW Forever Live

[Download the installable addon](https://github.com/travisejones28-alt/VoidMark-Market/raw/refs/heads/main/dist/VoidMarkMarket.zip). Install the `VoidMarkMarket` folder under `_forever_/Interface/AddOns`. If the game folder links to your GitHub Desktop checkout, pull `main` instead. Use the same version on both accounts.

Open the Auction House and use the **Shopping**, **Selling**, **Listings**, and **VoidMark** tabs. Auctionator can be disabled. Use **/vmm** for the standalone window. Safe Mode has been removed. Market starts closed, never trades at login, and doesn’t send orders from timers, scans, shopping lists, or received messages. Your existing account’s settings, history, ledger, pending purchases and cost basis stay in its own SavedVariables.

## What changed in 1.7

- Auctionator-style tabs on the Auction House: **Shopping**, **Selling**, **Listings**, and **VoidMark** (Scanning, History, Vendor, Crafting, Settings, Tools). With Auctionator also enabled, VoidMark's trading tabs are labelled **VM Shopping**, etc.
- Left-drag any empty part of the AH to move it. Right-drag the title bar to resize. Position and size are remembered (MoveAny overrides this when installed). **Settings > Reset Window** restores the default.
- Hover any item: price per unit, stack total for bag stacks, and whether the price is **CURRENT** or **STALE**, with its source and age.
- After updating both accounts, the bank re-offers its older scan prices once so the main catches up.


## Set up the bank alt and main

On any auction tab, left-drag the gold title bar to move the whole window. Hold the right mouse button and drag right to enlarge it or left to shrink it. With MoveAny managing the AH, its lock, modifier, scale and position settings apply.

1. In **Settings → Sync partner**, enter the **other** character’s `Name-Realm` on each account and click **Pair**. Alternatively use `/vmm peer Name-Realm`. Both characters must be on the same realm and faction.
2. Keep both characters online. Market uses the shared group when available. Otherwise it sends a private addon whisper directly to the configured character. A partner reply confirms delivery. Unanswered probes back off to once every five minutes. Combat or client chat restrictions may pause delivery.
3. At the AH on the bank alt, click **Full Scan**. On the main, hover over the same item. The **VoidMark Market** section shows the lowest observed price **per unit**, the source, and how old it is. A reliable historical estimate appears when available. The displayed ask is cached and can change before you buy.
4. **Shopping** works like Auctionator's: lists on the left open like folders (+/−) and search every item; click an item to search just that one. Hover icons search, rename or delete a list; **New List**, **Import** and **Export** sit underneath. Type a name and press **Search** (it becomes **Cancel** while searching); **More...** adds exact-name, max-price and min-available filters; **Add to List** adds the selected result to the open list. Click column headers to sort. Left-click a result to buy, right-click for price history, shift-click to copy its name. Changes, including removals, sync. The original watchlist remains the default **Shopping** list.

Use `/vmm peer` for status, or `/vmm peer off` to unpair. Initial catch-up takes longer than later updates. Messages are paced, batched and acknowledged; missing pages are retried and acknowledged progress survives reloads. Unchanged asks use a small timestamp update. Transactions, inventory, gold balances, crafting depth, and historical scan series stay local.

**Offline:** In **Transfer**, choose **Export Prices**, then copy and **Import Pasted Text** on the other client. Use **Next Prices** for additional pages (100 item keys per page). **Export Shopping** exports the active list; **Import Shopping** adds missing entries and preserves existing targets. You can move the text between PCs while either account is offline. Keep the two accounts’ SavedVariables separate.

## Trade from Market (1.6)

The main navigation is **Shopping, Selling, Canceling, Vendor Deals, Crafting, Tools**.

| Screen | What to do |
|---|---|
| **Shopping** | Type an item name and press Enter or **Search** for current AH results. Saved lists are on the left. Select an item, then **Buy Item**, **Compare Listings**, or **Add to List**. Bank scan prices are searchable even away from the AH. |
| **Buy Item** | Choose quantity and **Check Price**, then **Buy**. Commodities require **Confirm Buy** after the price quote. Regular items buy one complete listing per confirmation. |
| **Selling** | Choose a bag item, check its current price, enter quantity and gold per unit, then review and confirm the posting. |
| **Canceling** | Refresh your auctions, select a listing, and review its cancellation fee before confirming. |
| **Vendor Deals** | Scan the AH for buyouts below vendor sell value. The list includes small profits regardless of flip filters. Select a result to check its live price. An empty state explains when no eligible deals were found. |
| **Tools** | Bank sync, saved lists and targets, scan overview, flip opportunities, history, investments, purchase queue, ledger, settings, and diagnostics. |

The status bar distinguishes waiting, processing, calculating, stopped, and failed scans. A countdown after a failed request is a cooldown, not an ongoing scan. Detailed request logs are under **Tools > Diagnostics**.

Bank sync runs while both accounts are online; no party is required. Both characters must have the updated addon loaded. The status bar reports waiting, sending, receiving, or connected; **Tools > Bank sync** shows completed transfer times and received prices. Realm display spacing is normalized for incoming messages. Fractional stack unit prices are rounded up to the next copper for the price-only feed. Synced prices appear in item tooltips and Shopping, and purchases still check live listings. The price feed does not transfer complete historical scan series or transaction records.

## Verify on the live client

- With Auctionator enabled, open both addons and check bags, equipped items, and a clicked chat link. Compare a stack price divided by its quantity to the Market tooltip. Two different suffixes must not borrow one another’s price. Hover outside the AH: no AH query or sync request should start.
- Scan on the bank alt, reload the main during transfer, and verify the newest matching item eventually shows **Synced account**. Try a target edit and removal in a named list. Disconnect the partner and verify old data ages; test clipboard recovery. Reload and verify the ledger, pending entries, history and account-specific balances.
- At the AH, search for an inexpensive item. Open a regular purchase confirmation and cancel it. For an intentional purchase, verify the exact stack and total first. Test a commodity separately, letting one quote expire before requesting another.
- On **Sell**, compare the deposit with the native AH, then intentionally post one cheap item. Refresh **My Auctions**, check competitors, confirm the selected cancellation, then refresh again. Test any native second confirmation on the live client.
- Use `/vmm report` for build/API, scan, sync and transaction diagnostics. Controlled Lua tests exercise the workflows; they do not establish server delivery, in-game frame rate, or successful live transactions.

See [validation](VALIDATION.md), [the crafting release](RELEASE_1.4.md), and the [previous version’s full manual](https://github.com/travisejones28-alt/VoidMark-Market/blob/e7b6dea7d60de02850d6517315e750a225f2087b/README.md) for legacy migration and earlier behavior.


### Automatic cross-account synchronization (1.5.8)

The SYNC tab displays reciprocal pairing, actual reply status/channel, economy,
local and peer scan times, received price count, inbound/outbound revision progress,
last received page, completed receive and acknowledged send, and error diagnostics.
Voidmark Soulreaver and Voidmark Bank pair automatically on first initialization
in their realm/faction database. Existing explicit peers and subsequent `peer off`
choices are preserved. Other characters use the existing Settings peer field or
`/vmm peer First Surname`. Cross-realm pairing is rejected; every received packet
must match the configured peer and exact realm/faction economy.

Voidmark Bank requests a full scan automatically when its Auction House is open,
the 15-minute local cooldown permits it, and combat restrictions permit it. This
can be disabled in SYNC. Unsupported scan APIs are not called; failed attempts
are separated by at least five minutes, and the existing scanner handles queueing,
client throttles, response timeouts, and late responses. Opening an ordinary bank
alone cannot query AH prices. A client restriction or additional server cooldown
can still require a manual FULL SCAN click; diagnostics show the actual outcome.

Both accounts must be logged in concurrently with the addon enabled. No party,
raid, friend entry, or manual grouping is required by the addon: it uses targeted
addon whispers when no shared group exists. The server may restrict delivery;
queued messages are never treated as proof of connection. Offline probes back off
to five minutes and matching offline system errors are suppressed without hiding
unrelated chat errors. Reconnect clears runtime state; Force Sync changes the
journal epoch to replay the current latest states without deleting saved records.
Acknowledged receive cursors survive reload, pages retry on missing acknowledgments,
and unchanged asks transmit timestamp deltas. New metadata messages describe peer
scan time and total revisions; older peers still exchange prices but cannot supply
these additional diagnostic fields. Install the same version on both accounts.

Received prices immediately rebuild an open Browse view, remain visible with AH
closed, and appear on item tooltips. SYNCED / SYNC STALE labels, observation dates,
and age distinguish them from live quotes. Shared observations do not populate the
trusted local market model, transaction ledger, or execution eligibility. Trading
continues to require the existing live AH validation and confirmation controls.
SavedVariables remain separate for Beta and Live; links share addon code only.

Verification in game (not performed by the automated harness):
1. Reload both accounts on the same realm/faction. Open `/vmm`, then SYNC. Confirm
   reciprocal peers and a real reply while ungrouped; confirm a different faction
   or realm cannot exchange observations.
2. On Voidmark Bank open the Auction House and wait for the automatic full scan.
   Confirm scan completion, received prices, and completed transfer timestamps.
3. On Soulreaver close the AH, search Browse by a scanned item ID, then inspect its
   tooltip. Confirm the synced observation and timestamp; no live quote is implied.
4. Disconnect/reload one account mid-transfer, reconnect, and confirm it resumes.
   Force Sync should preserve shopping targets, history, settings, and ledger.
5. With the bank peer offline confirm quiet backoff; allow prices to age past the
   configured maximum and confirm stale labels and blocked execution without a
   fresh live validation. Repeat on Beta and Live independently.
