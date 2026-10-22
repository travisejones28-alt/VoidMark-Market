# VoidMark Market 1.3.0-beta

This increment extends the existing terminal and schema 1. It does not complete every objective in the overhaul brief.

## Implemented

- Browse: item-ID/name search, name/unit-price/spread/fair-to-ask sorting, player-requested live listing comparisons using the existing throttled complete-results reader. The four cheapest available tiers/listings show quantity, unit price and total. Comparisons expire after ten seconds and never authorize a purchase. REVIEW PURCHASE opens the existing revalidation workflow.
- Tables: reusable icons, item tooltips, selected-row highlighting, mouse-wheel paging and columns fitted to the table width. Saved position and scale with reset controls in Settings. No new addon dependencies.
- Charts: reusable native texture charts for up to 60 chronological scan medians or recorded gold observations. Samples are evenly spaced and labeled as observations, not sales/profit.
- Sniper: conservative, balanced and exploratory presets. These preserve transaction/exposure caps and Safe Mode; changing a preset invalidates prepared execution. Exploratory retains the baseline evidence minimums.
- Finance: UTC calendar-day buckets for 1/7/30-day booked results, fees, matched cost and uncosted revenue. Recording begins with this release; old bookings are not guessed or backfilled. Existing lifetime totals are preserved. Partial cost matching never assigns unknown costs zero profit.
- Wealth: per-character hourly gold/portfolio observations, capped at 720 samples and throttled to once per minute on money events. Gold history is not trading profit. Tracked wealth excludes unpriced positions and unknown-cost bags.
- Investments: age from the first newly recorded acquisition; legacy positions retain unknown age. Existing cost and history remain intact.
- Selling: per-variant preferred stack sizes (up to 300 preferences), with advisory plans limited by known item stack limits and selected bag quantity. No automatic splitting/posting.
- Banker: watched-price movements of at least 10% and downward price-target crossings between independent completed scans. Imported/untrusted/stale prices cannot produce these alerts.

## Validation

91 regression tests passed locally using the installed OBS LuaJIT Lua 5.1-compatible runtime through a temporary ctypes runner. The standard `Tests/run_tests.py` runner remains unchanged and uses stock Lua 5.1 via `lupa==2.8` in GitHub Actions. Local installation of lupa was blocked by network name resolution.

The scanner stress fixture now processes 90,000 rows over 883 synthetic-budget job ticks, including one invalid row. The synthetic 1,925 ms budget total is **not** a measurement of actual client latency. Tests cover existing purchase/quote safeguards, migrations, transfer isolation, UI construction, and new live-comparison, period accounting, charts, wealth retention, presets, layout, stack plans and movement alerts.

`python tools/package.py` and `python tools/package.py --check` verify every packaged member against canonical source bytes. No in-game visual or API testing was performed.

## Exact live checks

1. Close WoW and back up `VoidMarkMarket.lua` SavedVariables. Install `dist/VoidMarkMarket.zip` into the Forever AddOns folder. Do not remove SavedVariables.
2. Log in, open `/vmm`, confirm **SAFE MODE ON**, existing history and unresolved orders. Move the window, adjust Settings scale, `/reload`, and confirm layout persists while Safe Mode remains on.
3. At the AH click FULL SCAN. In Browse search an item name or ID, scroll/sort, select an item and click LIVE COMPARE. Compare quantities and unit/total prices with the native AH. Wait over ten seconds; confirm EXPIRED. Closing the AH must invalidate the comparison.
4. Click PRICE HISTORY. Check sample dates/medians against retained scans. Shared-only items must have no local history. GOLD HISTORY starts collecting from this version; legacy history is not invented.
5. Click REVIEW PURCHASE then REVALIDATE. Keep Safe Mode on for initial testing: EXECUTE must remain disabled. Test actual trades only after verifying client behavior and deliberately enabling trading.
6. Cycle Sniper presets; verify evidence thresholds change while spending caps remain unchanged. Review Sell stack plans for a stackable material and a single-item recipe; posting remains in the native AH.
7. Set a Shopping target. After a later fresh scan, check Banker movements. Cached analysis must not generate a new independent movement.
8. Review and book a verified invoice in Ledger. Confirm Overview period totals change once, unknown-cost proceeds remain separate, and deposits refunded by mail are not profit. Check an unresolved purchase still reserves funds after reload.
9. Use `/vmm report` for API diagnostics and report any Lua errors or clipped controls with a screenshot.

## Remaining work and access limits

- Direct posting/cancellation, automated stack manipulation and trusted-peer addon messages remain unimplemented pending source/API verification. Native AH posting/cancellation and manual account transfer remain available.
- Live Browse compares an already indexed exact local market; it is not a full server-wide text browser. The existing 300 cached-result cap and 1,000 live-tier/listing cap remain.
- Named shopping lists, category allocation, opportunity outcome attribution, robust sale-velocity evidence, unrestricted resizing and richer interactive charts remain future work. Asking-price movements do not prove liquidity or executed sales.
- The eight-addon compatibility review already in `REFERENCE_REVIEW.md` predates this increment. This session could not download the archives because the local transfer failed. No fresh archive inspection or direct source copying is claimed. The supplied reuse authorization is accepted; existing notices remain unchanged. Newly uploaded AuctioneerSuite is an additional reference, not silently covered by the eight-addon review.
- No files in the installed `C:\WoW Forever Addons\VoidMark-Market` checkout were modified. Deploy the GitHub package or update that checkout before testing.
