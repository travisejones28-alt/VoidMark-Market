# Reference Addon Compatibility Review — 2026-10-21

Eight user-supplied ZIP archives were opened, checked for manifests, dependencies, Lua module coverage, licensing and representative API paths. This is a static-source review; declared Interface 16001 is **not proof** that a component works on the actual Forever beta. No WoW client available in the test environment.

## Archive findings and adoption decisions

| Archive | Target manifest | Distinctive areas examined | Compatibility and action |
| --- | --- | --- | --- |
| Auctionator-341.zip | 16001 and other WoW versions | Source_ModernAH & Source_LegacyAH selling, shopping and browse providers; price history; posting mixins | Complex multi-flavor addon. Adopted simplified navigation, sorting and shopping targets; do not blindly import Retail or legacy code |
| auxForever-0.7.1.1.zip | 16001 | tabs/sniper/core.lua, core/scan.lua, tabs/post/core.lua | Local deal lifecycle and manual inspection queues are relevant. Avoid lifting background transaction behaviors without user-click/revalidation checks |
| ForeverForge_Auction_2.1.2.zip | 16001 | Query.lua, Market.lua, Sniper.lua, Post.lua, Share.lua | **Requires ForeverForge Core 2.0.0 or newer** for its full feature set. Preserve in-house AHQueue rather than introducing dependency; adopt ideas for throttled search and risk controls |
| AHledger-0.9.6.zip | 16001 / 11509 | Deals.lua, Prices.lua, Mail.lua | 30-day median deals and invoice-aware accounting. New 7/30-day snapshot median analytics informed by this reference, without counting disappearance as sales |
| AuctionHouseForever-v2.4.4-forever.zip | 16001 | Scan.lua, Prices.lua, Share.lua | Compact scanned price summaries and explicit sharing protocol are informative. New **manual transfer** is opt-in; no chat-channel broadcast |
| AbsoluteAuctionHouse-1.1.0.zip | 16001 / 120105 | Core/Scanner.lua, Core/Query.lua, UI/Shop.lua, UI/Sell.lua | Clean search UI and frame-budget processing. Never adopt unprompted scan-on-AH-open behavior, as it conflicts with the requested user-initiated scanning |
| market-addon-0.20.0-candidate-30fdf06.zip | 16001 | Depth.lua, Positions.lua, Prices.lua, Trades.lua | Audit cash verification, depth completeness, investment lots; preserve VoidMark's conservative ledger and unknown-order reservation |
| AuctionDB-v1.09.0.zip | 11507, 50500, 110200 (different manifests) | AuctionDB.lua, MoLib/MoLibAH.lua | **No matching Forever 16001 manifest**. Reference ideas only; do not import its older auction API directly |

## Licensing/provenance
The user reports receiving explicit permission from the reference authors to place adapted code on their public GitHub repository for inspection. Maintain original source notices and third-party licenses for any code/assets directly reused. Bundled metadata: Market and AuctionHouse Forever use MIT; AuctionDB uses GPLv3; Auctionator declares All Rights Reserved; ForeverForge Auction and Absolute AuctionHouse carry explicit restrictive notices; AHledger and auxForever do not include a clearly named standalone license in the uploaded ZIPs. This is not a legal determination.

**No wholesale source modules or external artwork were imported in this increment.** Original implementations were built using observed behaviors and public addon APIs. Future direct reuse should log exact originating filename, version and attribution; keep GPL-derived code separate from incompatible license assumptions. A copy-permission claim alone does not remove attribution or other applicable conditions.

## Integration completed from reference review
- 7-day and 30-day medians from independent **full-scan** price snapshots, not invoice prices or listing-count-weighted fake observations.
- Expanded SNIPER sorting: score, net profit, ROI, model confidence, inferred liquidity, discount, asking price and name, with blocked candidates visible.
- Manually exported validated price summaries for two WoW accounts on the *same* realm/faction. Account boundaries stay separate; imported prices stored in `db.sharedPrices`, never `db.market` or `db.ledger`. Imported snapshots cannot grant buy eligibility, alter history, trigger unattended actions or copy gold balances.
- Price transfer capped at 100 entries and seven-day export age, with integer/range/variant checks, duplicate rejection and bounded retained cache. This is **advisory**, not a background sync protocol.

## Deferred features needing continued Forever live testing
- Confirm retail-style commodity search, posting and cancellation APIs against actual Forever build; player-controlled only.
- Evaluate multi-stack selling/reposting and deposit capture with native Forever UI and reference workflows.
- Improve cost-basis matching for gathered, mailed and transferred inventory without pretending unknown costs are known.
- Add richer price chart and proven volume/sale evidence where genuinely available.
- Calibrate scan cadence and processor latency at 90k+ rows in the actual client.
- Manual transfer requires copy/paste between accounts. Addon channels require separate opt-in, trusted-peer checks and permission review before considering any network sync.
- Preserve all existing SaveVariables under schema 1; evaluate new migrations non-destructively before changing.

## Validation
Use `python Tests/run_tests.py`, `python tools/package.py`, then `python tools/package.py --check`. The mock harness executes all TOC Lua modules. User should live-test with Safe Mode ON, verify browser trends, export/import into same economy on both accounts, confirm differing faction/realm rejected and no trusted model changes, then inspect live buy revalidation (no purchase needed).
