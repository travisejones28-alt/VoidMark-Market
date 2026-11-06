# VoidMark Market 1.5 — WoW Forever Live

[Download the installable addon](https://github.com/travisejones28-alt/VoidMark-Market/raw/refs/heads/main/dist/VoidMarkMarket.zip). Install the `VoidMarkMarket` folder under `_forever_/Interface/AddOns`. If the game folder links to your GitHub Desktop checkout, pull `main` instead. Use the same version on both accounts.

Open the Auction House to use the **Shopping**, **Selling**, **Canceling**, and **Market** tabs. Auctionator can be disabled. Use **/vmm** for the standalone window. Safe Mode has been removed. Market starts closed, never trades at login, and doesn’t send orders from timers, scans, shopping lists, or received messages. Your existing account’s settings, history, ledger, pending purchases and cost basis stay in its own SavedVariables.

## Set up the bank alt and main

On any auction tab, left-drag the gold title bar to move the whole window. Hold the right mouse button and drag right to enlarge it or left to shrink it. With MoveAny managing the AH, its lock, modifier, scale and position settings apply.

1. In **Settings → Sync partner**, enter the **other** character’s `Name-Realm` on each account and click **Pair**. Alternatively use `/vmm peer Name-Realm`. Both characters must be on the same realm and faction.
2. Keep both characters online. Market uses the shared group when available. Otherwise it sends a private addon whisper directly to the configured character. A partner reply confirms delivery. Unanswered probes back off to once every five minutes. Combat or client chat restrictions may pause delivery.
3. At the AH on the bank alt, click **Full Scan**. On the main, hover over the same item. The **VoidMark Market** section shows the lowest observed price **per unit**, the source, and how old it is. A reliable historical estimate appears when available. The displayed ask is cached and can change before you buy.
4. Add an item and target to **Shopping**. Use **Open / Create** to create another named list or **Next List** to switch. Changes, including removals, sync. The original watchlist remains the default **Shopping** list.

Use `/vmm peer` for status, or `/vmm peer off` to unpair. Initial catch-up takes longer than later updates. Messages are paced, batched and acknowledged; missing pages are retried and acknowledged progress survives reloads. Unchanged asks use a small timestamp update. Transactions, inventory, gold balances, crafting depth, and historical scan series stay local.

**Offline:** In **Transfer**, choose **Export Prices**, then copy and **Import Pasted Text** on the other client. Use **Next Prices** for additional pages (100 item keys per page). **Export Shopping** exports the active list; **Import Shopping** adds missing entries and preserves existing targets. You can move the text between PCs while either account is offline. Keep the two accounts’ SavedVariables separate.

## Trade from Market

| Screen | What to do |
|---|---|
| **Browse** | Search cached items by name or ID. At the AH, **Search Live** searches by name; narrow broad results. **Live Compare** inspects current listings. **Buy Item** opens a manual purchase review. |
| **Shopping** | Add an item ID even before your first scan, or select a variant in Browse and switch to Shopping. Set a target in gold per unit. **Buy Selected** enforces that target at live review. |
| **Execution** | Choose quantity and **Revalidate**. Regular items buy one whole listing after confirmation. Commodities request a quote and require **Confirm Quote**. Stale or higher quotes cannot execute. Spending, quantity, reserve and affordability limits still apply. Only **Sniper** purchases require a profitable investment model. |
| **Sell** | Select a bag stack, choose quantity and duration, then **Check Price**. Enter **gold per unit** or review the suggested price. **Post…** shows competition, total proceeds before fees, and the current deposit. Confirmation submits the selected quantity once. |
| **My Auctions** | **Refresh My Auctions**, then select your listing to compare fresh competing prices, excluding your own. **Cancel Selected…** displays the current fee; confirm to cancel that auction. Reposting is a separate action. |
| **Crafting** | Capture an open profession, or click **Nexus** to read supported learned recipes from the current character’s Nexus cache. Rankings and material plans use local, validated input depth. Nexus is optional. |

The overview, banker dashboard, Sniper, post and purchase review queues, investments, ledger, crafting projects, and price history remain available. **Full Scan** requests an independent AH snapshot; **Cached** does not create fresh historical evidence. **Settings** controls spending and model limits. If a purchase outcome is unknown, check the mailbox and ledger before reconciling it.

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
