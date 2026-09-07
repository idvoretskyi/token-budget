# CI Environment

The workflow tests portable logic on Linux and tests, builds, packages, and verifies
a development app on macOS. The packaged-process smoke check is not a UI test
and does not replace interactive real-Mac validation.

## Validation Snapshot

Verified [run 34158486547](https://github.com/idvoretskyi/token-budget/actions/runs/34158486547)
on **2026-09-07**, commit `35538763923054c8101251b9504e04e903021217`:

- All 78 tests passed with zero failures on both Linux/Swift 6.2 and macOS 26,
  including the adapter suite and shared informational-warning forecast policy.
- The native product built, the release app was packaged at `dist/TokenBudget.app`,
  and strict ad-hoc signature verification passed.
- The packaged process survived the five-second smoke check.
- The arm64 development ZIP was generated and uploaded with upload-artifact v5 as
  artifact `10031796936`, subject to seven-day retention.

These results cover synthetic tests and hosted-runner checks. There has been no
interactive real-Mac validation or validation of a real installation with user
data. Process survival does not establish that the UI or notifications work.

## Runner Selection

Verified against official sources on **2026-09-07**:

- The [runner-images available-images table](https://github.com/actions/runner-images#available-images)
  lists `macos-26` as the standard macOS 26 **arm64** hosted runner. The similarly
  named Intel image documentation is not the reference for this label.
- The [arm64 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
  lists stable `/Applications/Xcode_26.6.app` with macOS 26.5 SDK. CI selects that
  installed version explicitly through `DEVELOPER_DIR`. Xcode 27 preview is not
  selected. The deployment target remains macOS 26.0.
- CI logs OS, architecture, Xcode, Swift, SDK version, and SDK path, and fails unless
  the host OS and SDK are 26+ and the selected Xcode is 26.x. If the installed path
  is removed, update it from the official inventory; do not silently downgrade.
- Linux uses `ubuntu-24.04` with the official `swift:6.3.3-noble` container and installs
  `libsqlite3-dev` plus `pkg-config` using apt. The
  [official image manifest](https://github.com/docker-library/official-images/blob/master/library/swift)
  lists the Swift 6.3.3 Ubuntu 24.04 image for amd64 and arm64. The
  [Docker Hub tag API](https://hub.docker.com/v2/repositories/library/swift/tags/6.3.3-noble)
  confirmed an active image; `.github/ci/Dockerfile` pins its multi-platform index digest,
  `sha256:56ef1be2c1ca36f4c52440357dc1fcdfdb5e113587134fcadeef57c225c71b54`.

Image inventories change and runner capacity or repository policy can still block
a job. The version checks intentionally fail rather than imply validation on a
different platform. The artifact is arm64, not a universal macOS build.

## Action Provenance

Full commit references were resolved from GitHub's API using `gh`, not copied from
an unverified example:

| Action | Queried ref | Verified commit |
| --- | --- | --- |
| `actions/checkout` | `v7.0.1` | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/upload-artifact` | `v7.0.1` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |

To review future updates:

```bash
gh api repos/actions/checkout/commits/v7.0.1 --jq .sha
gh api repos/actions/upload-artifact/commits/v7.0.1 --jq .sha
```

Both pinned actions declare `runs.using: node24` and require Actions Runner
2.327.1 or newer, supplied by GitHub-hosted runners. Checkout retains its default
unsafe-PR protections; no privileged PR checkout override is enabled. Upload uses
explicit `archive: true` to preserve named ZIP artifacts rather than v7's optional
single-file direct-upload mode.

Tags can move; review the upstream changes before replacing a pin. Container
digest pins also need deliberate updates to receive toolchain and OS fixes.

## Dependency Maintenance

`.github/dependabot.yml` checks GitHub Actions and Docker dependencies daily at
07:00 UTC (GitHub's daily cadence runs on weekdays). The Docker ecosystem reads
the `FROM` pin in `.github/ci/Dockerfile`, which CI builds and runs against a
read-only checkout with networking disabled during tests. Dependabot's Docker
fetcher does not discover arbitrary workflow YAML, so no duplicate image pin is
kept in the workflow. The GitHub Actions ecosystem maintains action references.
Both retain immutable commit/digest pins.
Minor and patch version updates are grouped per ecosystem; major upgrades remain
separate PRs. The limit is five open version-update PRs per ecosystem. Security
updates follow GitHub advisory support independently of this version-check schedule.

Dependabot alerts and automated security fixes are enabled in repository settings,
as are secret scanning and push protection. Version-update PRs run the same
unprivileged Linux tests and macOS tests/build/package/smoke checks as other PRs.
No auto-merge workflow is configured. Review release notes and require successful
CI before merging; this is a maintenance policy, not a claim of a branch ruleset.

Xcode paths, hosted runner labels, OS SQLite, and supported OpenCode/Codex input
schemas are not managed by these Dependabot entries. Review stable Xcode updates
against the official runner inventory. Hosted images and apt supply OS package
updates; system SQLite on user Macs is maintained with macOS. Never widen parser
version gates without source review and synthetic regression tests. Do not choose
preview toolchains or raise the macOS deployment target during routine updates.

There are no external Swift package dependencies, so no empty Swift Dependabot
job is added. Add a supported Swift entry when dependencies are introduced. The
manifest's Swift 6.0 tools minimum is distinct from the current CI compiler and
does not need to increase on every compiler update. Reverify both platforms after
all toolchain updates and update this document when pins or paths change.

## Permissions and Artifacts

Only `contents: read` is granted, checkout does not persist credentials, and there
is no `pull_request_target`, secret-dependent signing, release publishing, or
write permission. Pull requests run on hosted disposable runners. No real usage
fixtures or private logs belong in CI.

The packaging contract is `bash scripts/build-app.sh` producing the
release-configuration `dist/TokenBudget.app`. Bundle creation and signature
verification passed in the recorded run above.

The workflow requires the bundle and verifies it with
`codesign --verify --deep --strict`; it does not re-sign an invalid bundle to hide
a packaging failure. `ditto` creates a ZIP preserving bundle metadata before
upload. Only that ZIP is uploaded, with seven-day retention, not the workspace,
test logs, or a user's local data.

The smoke step starts `dist/TokenBudget.app/Contents/MacOS/TokenBudget`,
waits five seconds, checks process existence with `kill -0`, and terminates it on
step exit. This catches immediate process exits, not broken UI, settings, imports,
permissions, or notification delivery. It passed in the verified run above.

A passing ad-hoc signature check is an integrity check, not Developer ID signing,
notarization, a Gatekeeper assessment, or proof the app works interactively.
Interactive validation and production distribution remain open work.
