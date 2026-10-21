# VoidMark Market — overhaul audit and staged validation

Audited against `main` beginning at commit `d6612fb` (2026-10-21).
First implemented increment: 1.1.0-beta. Reference addon ZIP comparison is **pending** user uploads.

## Preserve and reuse

| Module | Observed role / preservation constraint |
| --- | --- |
| Core.lua | Event routing, budgeted job scheduler, realm-aware item variant keys, slash commands, safe lifecycle |
| Database.lua | Schema 1 realm+faction economies; additive migration; legacy import; pending identity restoration; newer-schema read-only guard |
| APIProbe.lua / AHQueue.lua | Capability probing; serialized, throttled AH requests; pagination and freshness checks |
| Scanner.lua | Forever replication scan and cached parsing; cooldown, deferred item data, incomplete-row rejection, progress reports |
| MarketModel.lua | Depth-weighted fair pricing (quartile / median), bounded history, confidence, volatility and activity *proxy* |
| OpportunityEngine.lua | Candidate ranking and risk gates; pending-capital reservations, quote freshness, exposure limits |
| Execution.lua | Player-click execution only; live revalidation; commodity quote confirmation; unknown outcomes stay reserved |
| Selling.lua | Banker's bag and owned-auction observations; price suggestions; native AH performs posting/cancel |
| Ledger.lua | Known acquisition basis, invoice observation, reviewed booking, unresolved purchase accounting |
| UI.lua / Minimap.lua | Existing purple identity, startup-closed behavior, settings, UI tables and minimap launcher |
| Sync.lua | Validation-only protocol boundary; **no** cross-account sync currently enabled |
| Diagnostics.lua | Full scan reports and copyable diagnostic export |

### Implemented without external reference archives

- 9 primary navigation screens, including distinct cached Browse, watch-target Shopping, Holdings/Investments, and Banker Mode
- Purple financial summary cards with tracked gold, available capital, known acquisition costs, conservative estimated liquidation, realized result, and unresolved spend
- Capped, budgeted Browse query over existing *local indexed snapshots*; no unsanctioned background AH requests
- Up to 200 realm/faction-local Shopping targets (base item IDs or selected variants). A target qualifies only with fresh cached data; no automatic purchase
- Player-configurable minimum liquid-gold reserve, with every live purchase evaluated against pending reservations and all earlier checks
- Portfolio valuation restricted to own recorded acquisition lots; stale/unpriced lots explicitly excluded from unrealized performance
- Fresh-scan Banker change log retaining bounded new *passing* candidates. Cached reanalysis cannot create new scanner evidence or alerts
- Additive SavedVariables keys only; schema version remains 1 to preserve Nexus price reading; no inventory/ledger/history reset
- Existing `/vmm`, old detailed screens, execution protections, and native Sell advisory mode remain available

## Current limitations and remaining work

1. **Reference addon comparison:** Audit Auctionator, auxForever, ForeverForge Auction, AHledger, Auctioneer Forever, Market, AuctionHouse Forever, Absolute Auction House and AHDB after ZIPs are uploaded. Feature-detect in-client capabilities and review licenses independently.
2. **Sniper:** Current existing ranking and risk gates are functional, but complete financial-metric column sorting, saved presets, queue presentation, and category-level exposure are still future improvements.
3. **Buying:** Existing safe clicks, native queue and revalidation are retained. Browse is cached market history and is not yet a complete live Shopping replacement for Auctionator.
4. **Selling:** Price suggestions and competition observation are advisory. Player-driven batch posting, stacks, cancel/repost queues and deposit verification are not implemented and must be conditioned on confirmed Forever APIs.
5. **Portfolio:** Only recorded, cost-tracked purchases are valued; gathered, mailed and unknown-basis assets require an explicit, evidence-aware inventory workflow. Realized profit is not inferred from missing auctions.
6. **Two accounts:** `Sync.lua` remains intentionally disabled. WoW SavedVariables do not cross-install/account-share automatically. Investigate explicit versioned manual transfer with trusted validation before adding any communication.
7. **Visual analytics:** Summary cards are complete for this increment; time-series native WoW charts, trend drilldowns and categorized profit charts remain to be built.
8. **Market learning:** Existing historical model requires repeated independent scans and avoids one-snapshot certainty. Liquidity is a supply/depth *proxy*, not observed sell-through. Server launch and early-market behavior need ongoing live calibration.
9. **Nexus:** Verified `VoidMark-Nexus/VoidMarkNexus/Prices.lua` reads Market schema 1 realm/faction data with confidence timestamps and invokes `SetView('opportunities')`. This contract remains intact; no hard Nexus dependency introduced.

## Automated validation

- GitHub Actions: `Validate Market` job for commit `f503352`, succeeded on 2026-10-21.
- `python Tests/run_tests.py`: **67 Lua 5.1 mock tests passed** including 4 added tests for reserve, watches, portfolio and fresh-scan changes.
- `python tools/package.py` / `--check`: **19 source files packaged and verified** against installable `dist/VoidMarkMarket.zip`.
- Tests verify deterministic addon logic and mocked frame construction, **not** actual in-game rendering, auction permissions, live transaction events, server cooldown or 90k-snapshot frame pacing.

## Forever beta manual test checklist

1. Back up each account's `WTF` SavedVariables before installing; replace addon code only.
2. Extract `dist/VoidMarkMarket.zip` into `_classic_beta_/Interface/AddOns/` and verify `VoidMarkMarket/VoidMarkMarket.toc`.
3. Log in both accounts separately. Confirm no startup transaction, Safe Mode ON, window starts hidden, `/vmm` opens the purple terminal.
4. On banker, open Orgrimmar AH; run a user-initiated FULL SCAN and watch progress. Check incomplete-row reports and verify cached analysis does **not** move last fresh observation timestamps.
5. Check Browse name filters, Shopping watch target add/update/remove, TARGET-to-STALE transition, Banker candidate deltas after a later successful fresh scan (respect cooldown), and page switching.
6. Verify live revalidation rejects stale and higher-priced listings. Keep Safe Mode ON unless explicitly testing a tiny permitted user-click trade. Test commodity quote with a separate confirmation click.
7. Ensure unknown transactions remain reserved through /reload; sale invoices do not silently become realized profit.
8. Compare investment known basis, fresh estimated liquidation and unpriceable positions with recorded ledger entries; inspect whether reserve setting prevents the proposed spend.
9. Test SELL and MY AUCTIONS with a known bank bag and auction; ensure no autonomous posting/cancellation.
10. Test Market + Nexus together and separately; inspect item price freshness by same faction/realm. Repeat after /reload.
11. Stress actual 50k–90k replicate rows; capture FPS, scan duration, error messages and `/vmm report`. Measure in actual client rather than claiming mock benchmark timings.
12. Retest under `_forever_` when released; **do not** assume `_classic_beta_` interface/API behavior is identical.

No automation, simulated click or unattended trading has been added.
