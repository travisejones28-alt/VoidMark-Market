# 1.3.1-beta: stress-test pricing corrections

The first live stress-test snapshot completed successfully: 551 valid rows, 99 markets, no missing/invalid records, 320 ms reported processing and no queue retries/timeouts. It also exposed extreme asking prices being presented as selling suggestions despite low-confidence warnings.

## Fixes

- Selling now requires at least three independent local observations, confidence at least 42 (or a higher configured minimum), acceptable volatility, fresh data and a trusted complete model. All four strategies withhold quotes and projected proceeds/profit when these checks fail. Status is UNPROVEN with the reason in the selected-item detail. This is an evidence gate, not a guarantee that repeated listings reflect actual sale value.
- Portfolio liquidation/unrealized gains apply the same evidence gate; unproven positions retain their cost but remain unpriced. Historical records, acquisition costs and original scan observations are not deleted or rewritten.
- Sniper hides resale fair-value/profit/ROI projections for unproven markets. Vendor comparisons remain separate. Browse labels these models UNPROVEN and retains observed asking prices/scan medians for investigation.
- Selling withholds a quote when estimated cut plus deposit allowance consumes all proceeds. It directs the player to check the actual native AH deposit rather than presenting negative proceeds as a recommended sale.
- Refreshed bag rows replace selected Sell details, avoiding a previous quote remaining visible after its evidence or inventory changes.
- Item icons use modern C_Item, legacy metadata and bag-provided texture paths with fallbacks. This addresses the question-mark icons in the screenshots; client rendering still requires verification.
- Manual transfer accepts Windows CRLF clipboard text and trailing newlines while continuing to reject malformed internal records, realm/faction mismatches and stale data.

## Validation

97 tests pass locally on the LuaJIT Lua 5.1-compatible runtime, including all previous transaction/scanner regressions and six new regressions. The Rough Arrow fixture uses the supplied 99,999,990,100-copper model, 30 confidence, one observation and a 200-arrow stack: no strategy returns a price, proceeds or profit, and no portfolio valuation is created. Other new checks cover volatility/confidence gates, fees consuming proceeds, icon API fallbacks, clipboard normalization and hidden unproven UI projections. The 90,000-row scanner fixture remains passing.

The package is rebuilt and checked against source members. This update was made while the servers were offline; no additional in-game verification is claimed.

## When the server returns

1. Install 1.3.1-beta and open `/vmm`. Keep Safe Mode on for these checks.
2. Sell should show UNPROVEN / No quote for Rough Arrow and other first-scan models, with no gigantic projected proceeds. Selecting a row explains the missing evidence.
3. Browse should retain real observed asks while its model column says Unproven. Sniper should retain blocked candidates but show `--` for unsupported profit/ROI.
4. Check item icons, then `/reload` and `/vmm report`: confirm persistence marker loaded is true and scan history remains.
5. Verify LIVE COMPARE against the native AH when it reopens. Source/API verification for direct posting and cancellation remains outstanding; those actions still use the native AH.
