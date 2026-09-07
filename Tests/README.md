# Market freshness regression checks

With full Xcode installed:

```sh
swift test --filter MarketDataFreshnessTests
```

Some Command Line Tools installations do not ship the `XCTest` module. On those Macs:

```sh
python3 Tests/run_freshness_checks.py
```

The fallback compiles a temporary copy of the current production Swift sources, excluding only the GUI entry point. It runs the same test methods with Foundation assertions, exits with a nonzero status on failure, and prints the source snapshot SHA-256. It requires no third-party Python packages. Compiler modules are cached separately under `.build/freshness-module-cache`.

The checks use a deterministic clock and mocked service responses. They cover source age boundaries and clock skew, independent refresh cadences, partial data, cached values after failure, recovery, request cancellation and retry, ETF report dates, exclusion of stale context and core quotes from the market interpretation, retained domestic data status, concurrent domestic fetches, cancelled/older domestic responses, complete share-summary sentences, and full caption timestamps with explicit time zones. Test models disable background work and do not load or update the user's domestic radar history.

These regressions do not establish live provider availability, market-data accuracy, UI layout, or Intel compatibility; those require separate verification.

## Installation recovery

```sh
bash Tests/install_transaction_test.sh
```

Uses temporary synthetic bundles and a validator stub to test first install, update, rollback, validation failures, locking, interrupts at rename boundaries, and preservation of backups when automatic recovery fails. Does not launch Catoshi or modify the user's Applications directory.

## Launch identity and survival

```sh
bash Tests/launch_check_test.sh
```

Mocks process discovery, `open`, and waits. Eleven scenarios cover requested bundle identity, spaces, path aliases, delayed startup, early exit, process replacement, and validation/launch failure. No application is launched or terminated by this test. The production launch check verifies the same executable/PID for 15 seconds; UI and live data require separate checks.
