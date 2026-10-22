# VoidMark Market 1.3.1-beta

Current release: [1.3.1 stress-test pricing fixes and live checks](RELEASE_1.3.1.md). [1.3.0 features](RELEASE_1.3.md). Historical hardening release: see [HARDENING.md](HARDENING.md) for confirmed fixes, validation and in-game checks. Download the rebuilt addon from `dist/`.


A testable Forever auction terminal built from the supplied working prototype.
**This build has automated mock validation, but has not run inside the Forever client.**

## Install

1. Close WoW. Back up your current addon and its SavedVariables.
2. Extract the `VoidMarkMarket` folder into the Forever client's `Interface/AddOns` folder.
   The layout must be `Interface/AddOns/VoidMarkMarket/VoidMarkMarket.toc`.
3. Disable the old Taliaa Trade prototype. Start WoW and open `/vmm`.
4. Open the AH and choose **FULL SCAN**. Every login begins in **SAFE MODE**.
5. Test `/reload` and persistence before enabling trading. `/vmm report` includes a
   persistence marker; it should say loaded after a reload. The reference addons
   report historical Forever SavedVariables-loading problems; this build uses
   normal SavedVariables and does not copy their CVar workaround.

No reference addon, external framework, or additional library is required.

## Preserve prototype history

The new folder name changes the SavedVariables filename. Merely declaring the old
variable does not make WoW load another addon's SavedVariables file.

With WoW closed:

- Find the old prototype's account SavedVariables Lua file, usually
  `WTF/Account/<account>/SavedVariables/TaliaaTradeBeta.lua`.
- Back it up. On a first installation, **copy**, rather than move, that file to
  `VoidMarkMarket.lua` in the same SavedVariables directory. The copied contents
  should still assign `TaliaaTradeBetaDB = { ... }`.
- Start the new addon. It imports the old market records once into the current
  realm/faction book and retains the legacy global. `/reload` then writes the
  new database alongside it.
- If a `VoidMarkMarket.lua` already exists, do not overwrite it. Import the legacy
  assignment into a backed-up copy while WoW is closed, or ask for a file merge.

The old prototype did not identify realm/faction in its market root. Import it
on the economy where that data was collected. Do not assume cross-realm history
is compatible. No imported KOS, combat, or unrelated VoidMark data is used.

## Terminal workflow

- **Market:** scan status, counts, timing, generation, and known-cost summaries.
- **Opportunities:** up to 200 ranked candidates; name filter and score/profit/ROI/name sorting.
- **Execution:** select an opportunity, set a maximum quantity, then **REVALIDATE**.
  Full fresh search results replace the snapshot estimate. The panel explains
  economics, scoring components, risk blocks, and model inputs.
- **Settings:** transaction, item and portfolio exposure caps; quantity; minimum
  profit, ROI, confidence and liquidity; volatility, deposit allowance, cut and age.
- **Selling:** bag items with a market model; suggested unit prices and own-price protection.
- **My Auctions:** explicit owned-auction refresh; click a listing for fresh competition
  and cancel-cost analysis. Repricing reduces potential revenue and may lose
  deposits, so a small undercut does not justify automatic churn.
- **Ledger:** confirmed purchases, pending/unknown orders, invoices, observed mail
  outcomes, posting and cancellation events. Review entries before bookkeeping.
- **Diagnostics:** capability probe, queue/throttle counters, scanner, execution and logs.

### Trading

Turning Safe Mode off enables purchasing only for the current login.

Regular auction: **REVALIDATE → EXECUTE** buys **one whole auction**. Quantity is
an upper bound, not a request to loop over auctions. Bogus Forever quantities
for recipes/non-stackable items are capped conservatively to the item stack size.

Commodity: **REVALIDATE → EXECUTE → CONFIRM QUOTE**. EXECUTE requests a quote;
confirmation requires another real click within five seconds. A higher quote is
rejected. Revalidation expires after ten seconds. Aborted quotes impose a short
cooldown to reduce the chance of accepting a stale response.

No event or timer buys, posts or cancels an auction. Safe Mode permits all
research and blocks transactions. Native AH posting/cancellation remain available
through the game, not this addon's action callbacks.

Use this addon's purchase workflow alone while it has a quote or pending order;
commodity events have no order ID to distinguish transactions issued simultaneously
by the native UI or another addon. Server rejection after an item purchase remains
possible even with fresh prices.

A missing purchase result becomes **UNKNOWN**, not failed. Funds stay reserved,
including after reload. Check AH/mail and select the order in Ledger to record
confirmed success or failure. Manual outcomes are labeled as user reported. After
manually resolving a commodity, a two-minute guard reduces late-event ambiguity.

## Model and accounting

- Preserve the prototype's suffix-separated, quantity-weighted distribution model.
- Current depth value is 45% lower quartile plus 55% median; blend with recent,
  winsorized history. A lone low-priced item does not reset fair value.
- Confidence uses independent observations, depth, stability and elapsed history.
  Within-day history cannot reach the highest confidence bands. Observations are
  at least fifteen minutes apart; cached snapshots never refresh established history.
- Supply movement/depth is **inferred activity**, not measured sale velocity.
- After three reviewed seller invoices, observed sale prices can contribute at
  most 15% to the fair-value estimate, bounded relative to current depth.
- Scores combine absolute profit, ROI, confidence, inferred liquidity and depth,
  with volatility and capital penalties. Vendor spread uses a separate model and
  does not charge hypothetical resale fees.
- Expected resale net includes the configured AH cut and a conservative per-unit
  deposit allowance. Verify the cut for the AH you use. Deposits are not live
  quotes and repeat posting costs may exceed the allowance.
- Confirmed purchases create character-specific moving-average inventory cost.
  Sold quantity without known purchase basis is reported as uncosted revenue and
  excluded from cost-matched realized profit. Unobserved vendor sales, transfers,
  disposals and purchases outside this addon are not automatically reconciled.
- Seller invoices are observed, but expose no unique mail/auction ID. They require
  review before **BOOK REVIEWED SALE**. The invoice's winning bid takes precedence
  over an advertised buyout, and inconsistent payout amounts block booking.
  Refunded deposits are returned capital, not revenue. Untracked lost deposits
  and posting charges are not silently invented or included in realized results.
- Invoice fingerprints and occurrence counts suppress repeats conservatively.
  Identical later mail can remain indistinguishable and be suppressed; open Ledger
  and inspect it rather than treating the history as an exact bank statement.
  Expired/cancelled/outbid/won subjects from the system AH sender are observations,
  not inferred sales. Disappearance from listings never proves a sale.

## Boundaries and deferred features

- Intelligent posting and cancel/repost analysis are advisory. Direct post/cancel
  execution, complete deposit/lifecycle attribution and probabilistic sell-through
  optimization are deferred until the core is live-tested.
- Cross-client transmission is disabled. `Sync.lua` supplies a versioned validated
  summary boundary; no addon traffic or imported remote evidence is active.
- Histories retain at most 30 compact observations per market, recent sale samples
  at most 30, scan summaries at most 20, ledger detail at most 2,000 and mail
  fingerprints at most 5,000. Lifetime financial aggregates and unresolved orders
  survive detail pruning. Missing items retain their last useful observation.
- Archived markets retain their last price; at 20,000 indexed markets new markets
  are skipped rather than deleting useful history. Markets with more than 512
  distinct scan price tiers retain old history and are excluded from execution.
- More than 1,000 live result tiers/listings, unknown item classification, missing
  completeness APIs, corrupt result rows, or incomplete pagination block execution.
  These conservative limits can be revised after measuring real client behavior.
- Schema 1 migration is idempotent. A newer saved schema is left untouched and
  analyzed only in temporary memory with trading blocked.

## Prioritized live test

1. Keep Safe Mode on. Load, open every tab, complete a full scan, then close/reopen
   the AH and `/reload`. Verify counts, history, marker and pending data persist.
2. Pick a regular auction and a commodity. Revalidate twice, including after the
   same item was searched in the native UI. Verify refresh, pagination, variants,
   own-auction exclusion and displayed quantity/price. In Safe Mode, no buy occurs.
3. Confirm Settings limits reject an over-budget transaction. On a cheap item,
   deliberately enable trading and test one regular purchase, then one commodity
   request and separate confirmation. Match inventory/mail to recorded costs.
4. Let a commodity quote expire; change/remove a listing; close the AH during a
   request. Verify no stale confirmation and uncertain purchases remain reserved.
5. Inspect genuine sale/won/expired/cancelled mail, reload/reopen the mailbox and
   check duplicate handling. Review one seller invoice and verify cost basis,
   revenue, cut, deposit refund and realized/uncosted split.
6. Validate bag suggestions and owned-auction competition. Use `/vmm report` to
   report client API/event differences and any UI layout or Lua error.

Commands: `/vmm`, `/vmm scan`, `/vmm cached`, `/vmm diag`, `/vmm report`,
`/vmm probe`, `/vmm debug`.

## Source and validation

The working uploaded prototype remains the primary source. Its market model,
replicate return layout, suffix convention and capability probe were retained and
extended. ForeverForge Auction and AHledger were read selectively for API behaviors
and constraints; their source and frameworks are not bundled or merged.

`Tests/test_addon.lua` contains deterministic WoW mocks and behavioral tests;
`Tests/run_tests.py` runs them using the system Lua 5.4 shared library. Run
`python3 Tests/run_tests.py` from this folder in a Linux environment with that
library, or run the Lua harness with a compatible Lua interpreter from this folder.
The test harness is not loaded by the TOC. See `VALIDATION.md` for scope and results.

Repository: https://github.com/travisejones28-alt/VoidMark-Market

## 1.0.1-beta full-scan diagnostic test

The scanner uses `C_AuctionHouse.ReplicateItems`, not a legacy `QueryAuctionItems`
getAll request. The old 25-second response cutoff discarded the request even
though the 15-minute cooldown had already started.

- Full scans now wait 60 seconds, then keep the request active through 180 seconds
  without retrying it. Other search and transaction behavior is unchanged.
- After 180 seconds the queue is released, but a late replicate event can still
  recover the abandoned request during the same open AH session. Closing the AH,
  starting cached analysis, starting another full scan or reloading ends recovery.
- An empty or invalid replicate count is logged and does not publish an empty
  successful scan. Previously saved market history remains available.
- The Market tab and Diagnostics/report show the last request, pre-request cached
  count, response delay and count, parse start/finish, processing time and errors.
  The last 24 event records and total counters persist in SavedVariables.
- `REPLICATE_ITEM_LIST_UPDATE` is the accepted response. Legacy
  `AUCTION_ITEM_LIST_UPDATE` events are traced with `GetNumAuctionItems("list")`
  batch/total counts when that optional API exists, but are not consumed as a
  full replicate snapshot. An unchanged row count alone is not evidence of stale
  data; a nonempty replicate event is required, rather than polling cached counts.
- Duplicate events do not restart parsing. Processing remains frame-budgeted.

Update the addon, `/reload`, keep Safe Mode on and open the AH. Once the cooldown
ends, click FULL SCAN once and keep the AH open for at least three minutes if it
has not completed. Then use `/vmm report` and copy the diagnostics, even if the
scan fails. The report distinguishes no replicate event, legacy events only,
empty results, invalid counts, successful parsing and recovered late responses.
This is a diagnostic fix validated with mocks; live beta response behavior still
needs this test.

## 1.0.3-beta item-data recovery

The supplied live 1.0.1 report completed with 89,929 returned rows, 85,905 accepted
rows, 2,603 markets and 200 listed candidates. Response time was 5.875 seconds;
processing took 33.389 seconds. There were 3,476 replicate update events, 4,024
rejected rows and 8,040 incomplete counts. The old counter could count one row
with both missing metadata and a missing link twice; that is corrected here.

- Rows missing required pricing fields or a usable item link are deferred and
  reread across frames for up to 10 seconds after the initial pass (maximum
  20 retry passes, then a final bounded pass). A recovered row is added once.
- Known prices and links remain usable even if the optional hasAllInfo flag is
  false/nil; owner/display metadata is not required to value a known variant.
  Missing links are never guessed as suffix zero. Random-stat variants stay separate.
- Reports separate recovered and unresolved rows from no-buyout listings,
  unavailable sales, missing fields/links, and row API/parser errors. The
  incomplete count now counts distinct source rows once.
- Identical adjacent events are coalesced; total event counters remain exact.
  Repeated event log lines are limited to one per five seconds. Request and parse
  milestones remain visible, and elapsed times continue through parsing.
- A changed replicate row count while parsing aborts that snapshot before model
  publication; let the cache settle and choose CACHED to analyze it separately.
  No new replicate request is automatically sent.

Pull the update, `/reload`, keep Safe Mode on, and run FULL SCAN once when the
cooldown expires. Then copy `/vmm report`. CACHED can test the new row handling
without another server request, but it still does not refresh existing history or
increase confidence. We do not yet know how many of the live rejected rows were
loading late versus legitimate bid-only/otherwise unusable listings; the next
report now distinguishes those cases.

## Workstation overhaul — 1.1.0 beta (first increment)

New primary navigation: Overview, Browse, Sniper, Shopping, Sell, Investments,
Banker, Ledger, Settings. BUY REVIEW, MY AUCTIONS and DIAG remain accessible
from the upper toolbar. The market browser is a capped, incremental **cached**
search; it does not query live AH prices. Shopping stores up to 200 price targets
per realm/faction. Watch targets never trigger purchases. Banker highlights new
**passing** opportunities since the previous *completed fresh* scan, not cached
reanalysis. Portfolio net liquidation and unrealized results are **estimates**
only for positions whose historical valuation is fresh, whereas ledger sales are
tracked separately as confirmed/reviewed accounting. Liquid reserve is
configurable in Settings (gold), defaults to zero for backward compatibility,
and is enforced alongside pending reservations during live validation.

Important limitations: no automated repeat scans, instant cross-account sync,
posting/cancellation, proof of liquidity, guaranteed resale, or live client testing.
Unknown historical acquisition costs cannot be treated as realized profit.
Source references and API compatibility will be revisited after reference ZIPs
are supplied. Update the repo-installed addon from the packaged ZIP before use;
keep Safe Mode on for the first in-game checks.


### Reference-informed 1.1 beta increment
- SNIPER supports profit, ROI, confidence, liquidity, discount, ask and name sorting, and visibly distinguishes blocked candidates.
- BROWSE shows rolling 7-day / 30-day scan medians, with independent scan snapshots rather than listing counts as samples.
- TRANSFER (top-right) provides opt-in manual price summaries for two accounts on the same realm and faction. It serializes only 100 validated recent advisory market observations. Import never creates trades, trusted historical scans, or executable opportunities. Imported entries show as SHARED* in BROWSE. No addon channel broadcasts or unattended trading.
- This is a first integration of uploaded reference workflows, not a claim that all referenced features are implemented.

Version 1.1.1-beta: tested advisory manual realm/faction transfer, 7/30-day rolling scan medians and expanded sniper metric sorting. Explicitly excludes derived sales, automatic purchasing and foreign or mismatched variants from trusted market history.

Purchase review queue: select an opportunity in SNIPER, choose SAVE TO QUEUE in its execution review, and access BUY QUEUE in the top toolbar. The queue persists per economy but never quotes, bids, reserves funds, or completes a purchase. RECHECK entries must regain trusted fresh analysis before inspection. Each actual buy still requires live revalidation and a real click.


## Intelligent selling (1.2.0 beta)
- SELL scans all unbound bag items, including those lacking historical prices, and labels unknown or stale variants instead of silently omitting them.
- Strategy button cycles COMPETITIVE (meaningful lower-market floor, resisting isolated bait), QUICK (conservative discount), MEDIAN (model fair), and MARGIN (higher-ask approach).
- Item-specific minimum prices are stored per realm/faction in copper and can be cleared by leaving the amount blank. This is a pricing FLOOR, never an unattended post.
- The economic quote includes per-unit known acquisition basis from this character's purchase ledger, user-specified minimum, modeled AH cut and a deliberately conservative deposit allowance. When a stack is only partly costed, profit is UNAVAILABLE; do not treat gathered/mailed items as costed.
- Pricing holds/reviews excessively high minimums, suspicious low auction floors, poor confidence and volatility. No posting or cancellation APIs are called here. The native AH remains the only posting interface.
- Real Forever deposit quotes, stack splitting, and posting lifecycle remain subject to live API verification.


### Cancel/repost advisory
On MY AUCTIONS, click your listing to request a fresh complete search of competing prices. The recommendation is HOLD unless a material gap is verified, meaningful depth supports it and the native client returns the cancellation fee and the existing listing deposit. A REVIEW state provides cost impact only, never a cancellation command. An unknown fee, unmodeled competitor or stale market prevents cancel recommendations. Selling Settings now include a configurable known-cost minimum margin (0-200%).


### Posting review queue (1.2.1 beta)
Select an item in SELL, choose QUEUE POST to save a per-character/economy posting intent, then POST QUEUE to review it. Nothing is posted. Bag slots, live prices, deposits and stack ownership are NOT persisted as authority. Each revisit rescans available bags and recalculates conservative prices. Only advisory HOLD/NO PRICE/CHECK BAGS/REVIEW statuses are shown; actual posting remains a native Auction House user click.
