# VoidMark Market 1.0.3 beta — hardening review

Reviewed main at `7a85475`. Existing history, settings, pending orders, cost basis and user-reviewed bookkeeping are retained. Market still stays closed on login and starts in Safe Mode.

Confirmed fixes:
- Invalid/non-finite/fractional auction identities are rejected; two missing identities cannot compare equal. Suffix, level and pet variants remain distinct.
- A future or invalid saved market timestamp cannot satisfy the resale freshness gate.
- Invalid invoice quantity, gross or fee is rejected before booking revenue or changing inventory basis.
- An unmodeled saved market is skipped by the inventory selling reader rather than triggering arithmetic on a missing fair value.
- Non-finite monetary display values render as unknown instead of crashing a panel.
- The Market panel uses MEDIUM strata and native top-level focus behavior, matching Nexus's application panel instead of permanently dominating it. Purchase, quote, confirmation and uncertainty rules are unchanged.

Validation: **63 stock Lua 5.1 mock tests** pass. These include full-scan deadlines, deferred rows, bounded 3,500-event bursts, suffix identity, stale data, live revalidation, Safe Mode, quote expiration, uncertain reservations and bookkeeping. New tests cover the confirmed hardening fixes. The test runner now uses cross-platform `lupa==2.8` rather than a Linux-only Lua 5.4 shared library. A four-addon integration verifies closed-on-login behavior, matching/foreign economy pricing and declared frame layers.

Installable ZIP: `dist/VoidMarkMarket.zip`; `python tools/package.py --check` compares canonical sources. Run `python Tests/run_tests.py` after installing `lupa==2.8`.

In-game: keep Safe Mode enabled while checking startup, scan/cached reports, panel focus, selling rows and a known item's Nexus price. Verify data age and suffix separation. Protected purchase confirmation and server AH event schemas cannot be proven by mocked tests; do not infer live transaction success from these results. Existing historical and unresolved financial data is not destructively pruned by this update.
