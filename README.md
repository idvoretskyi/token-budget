# Token Budget

An open-source, native macOS 26+ menu bar app for estimating the cost of locally
observed OpenCode and Codex CLI usage. Built with Swift and SwiftUI, with no runtime
network requests, telemetry, backend, or API credentials.

## Experimental Status

This is an early MVP, not a production-validated financial tool. Native build and
packaging are verified: [CI run 34158262112](https://github.com/idvoretskyi/token-budget/actions/runs/34158262112)
at `abe383f` passed all 77 tests on both Linux and macOS 26, packaged the release
app, verified its ad-hoc signature, and generated an artifact on 2026-09-07.
**No interactive real-Mac validation has been completed.** Permissions, menu bar
behavior, and notification delivery still need interactive testing. Subsequent
forecast-policy and process-smoke changes await CI; see [CI status](docs/ci.md).

Estimates are not provider bills, subscription allowances, prepaid balances, or
enforced spending caps. Missing history, unsupported log formats, unknown prices,
and provider-specific accounting can make estimates incomplete. Token Budget is
not affiliated with OpenCode, OpenAI, or any model provider.

## MVP Scope

- Read local OpenCode and Codex CLI usage from explicitly enabled sources.
- Scope a budget to selected source/provider/model combinations, not every account
  or provider automatically.
- Use weekly or monthly periods in a configured, fixed time zone. Traveling or
  changing the system time zone must not silently change a budget period.
- Start with manually entered, dated price profiles, including currency and rate
  provenance. There is no automatic price feed or provider account lookup.
- Treat refresh as a full-rescan MVP. Incremental imports and broad format
  compatibility are not promised.
- Optionally notify at new 80% and 100% crossings of the recorded, priced budget
  estimate, after a silent baseline scan. These are not billing or allowance alerts.

The settings model starts with no enabled sources, selections, or prices, and
notifications off. Notification permission is requested only when enabling the
preference and applying settings. Local records cannot prove complete billing-period
coverage; any coverage start is a user assertion, not independent verification.

The current forecast policy requires confirmed coverage beginning at or before the
period start, at least 24 elapsed hours, fully priced usage, and no actual import
problems or unknown warnings. Informational coverage, canonical-step, and recorded
attribution notices remain visible but do not suppress it. This policy update
awaits CI verification. See [pricing and alert semantics](docs/pricing.md).

### Initial Setup

1. In Settings, enable a local source and choose its input location, then apply
   settings and refresh. No credentials are needed.
2. Select the discovered source/provider/model combinations to include.
3. Configure the budget amount, currency, weekly or monthly reset, and time zone.
4. Enter a dated price profile for each selected model with all four token rates
   and provenance. Enter an explicit zero only for a category known to be free.
5. Apply settings and review import warnings and unpriced usage. Only confirm
   history coverage if you can independently justify it for the selected scope.
6. Optionally enable threshold notifications and apply settings to request macOS
   permission. The first eligible scan establishes a silent baseline, not historical
   alerts. Missing prices and import problems suppress alerts.

## Build and Test

On **macOS 26 or later**, install Xcode 26 with the macOS 26 SDK or newer and select
its developer tools. From the repository root:

```bash
swift test
swift build --product TokenBudget
bash scripts/build-app.sh
open dist/TokenBudget.app
```

The script builds a release-configuration app at `dist/TokenBudget.app` and signs
it ad hoc. The `open` command launches your local development build for manual
testing; interactive behavior is not yet validated. CI verifies the signature and
uploads a ZIP with seven-day retention. An ad-hoc signature does not establish
publisher identity or notarization, and the arm64 CI artifact is not a universal
binary or a production release. Do not disable Gatekeeper to run an untrusted build.

### Linux Checks

Swift 6 can test the platform-independent core and adapters on Linux. CI uses the
official Swift 6.2 Ubuntu Noble container. Install SQLite development headers and
`pkg-config` first (Ubuntu/Debian):

```bash
sudo apt-get update
sudo apt-get install --no-install-recommends libsqlite3-dev pkg-config
swift test
```

The package excludes the SwiftUI app target on Linux. Passing these tests does not
validate the macOS app, notifications, bundle, or code signing.

## Documentation

- [Architecture](docs/architecture.md)
- [Privacy](docs/privacy.md)
- [Pricing and budget semantics](docs/pricing.md)
- [Source compatibility](docs/compatibility.md)
- [Roadmap and validation gaps](docs/roadmap.md)
- [CI environment and provenance](docs/ci.md)
- [Contributing](CONTRIBUTING.md), [security](SECURITY.md), and
  [code of conduct](CODE_OF_CONDUCT.md)

Report non-sensitive bugs in the [repository issues](https://github.com/idvoretskyi/token-budget/issues).
Never attach real session files, databases, credentials, or raw diagnostic logs.

## License

[MIT](LICENSE).
