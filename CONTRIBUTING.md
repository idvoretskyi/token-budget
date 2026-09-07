# Contributing

Token Budget is experimental. Small, reviewable changes and synthetic regression
tests are more useful than broad compatibility or accuracy claims. Participation
is covered by the [code of conduct](CODE_OF_CONDUCT.md).

## Discuss and Develop

1. Check the [issues](https://github.com/idvoretskyi/token-budget/issues) for existing
   work. Discuss major product, storage, or shared-model changes before coding.
2. Read [architecture](docs/architecture.md), [privacy](docs/privacy.md), and
   [pricing](docs/pricing.md). Preserve the local-only runtime and explicit estimate
   semantics.
3. Make a focused change with tests that use invented data. Do not upload actual
   usage history, even if you believe it has been redacted.
4. Describe the behavior change and exact checks run in a pull request. Clearly
   separate Linux test results, native build results, and interactive Mac checks.

## Checks

On macOS 26+ with Xcode 26 and a macOS 26+ SDK:

```bash
swift test
swift build --product TokenBudget
bash scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 dist/TokenBudget.app
```

The package script produces `dist/TokenBudget.app`; native build, packaging, and
ad-hoc signature verification have passed in the [recorded CI run](docs/ci.md).
Use `open dist/TokenBudget.app` to begin manual testing of your local build.
Packaging and code-signature verification do not test interactive behavior or
notarization. The five-second CI process check has passed but is not a UI test or
validation of a real installation with user data.

On Linux, install Swift 6, `libsqlite3-dev`, and `pkg-config`, then run `swift test`.
CI uses Swift 6.3.3 on Ubuntu Noble. Linux intentionally excludes the SwiftUI app;
you do not need a Mac to contribute portable tests or documentation.

For import changes, test repeated scans, missing and malformed fields, cumulative
versus per-event counters, cache-category overlap, and unknown schema behavior.
For budgets and pricing, cover time zones, reset boundaries, effective dates,
missing prices, currency mismatches, and partial coverage as relevant.

## Safe Reports

Use the issue templates and describe a minimal synthetic reproduction. Include
tool versions and static warning text, not raw logs or environment dumps. Inspect
screenshots for identifying content before posting; prefer a synthetic-data
screen. Never include source databases, session files, prompts, private repository
names, absolute personal paths, API keys, or authentication files.

Report vulnerabilities through [SECURITY.md](SECURITY.md), not public issues.
Contributions are made under the repository's [MIT license](LICENSE).
