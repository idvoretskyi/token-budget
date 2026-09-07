# CI Environment

The workflow tests portable logic on Linux and tests, builds, packages, and verifies
a development app on macOS. The new packaged-process smoke check is not a UI test
and does not replace interactive real-Mac validation.

## Validation Snapshot

Verified [run 34158262112](https://github.com/idvoretskyi/token-budget/actions/runs/34158262112)
on **2026-09-07**, commit `abe383f3c992b2a3629ae9a97cb2804d7367ae25`:

- All 77 tests passed with zero failures on both Linux/Swift 6.2 and macOS 26,
  including the adapter suite.
- The native product built, the release app was packaged at `dist/TokenBudget.app`,
  and strict ad-hoc signature verification passed.
- The arm64 development ZIP was generated and uploaded as artifact `10031715299`,
  subject to seven-day retention.

Subsequent working-tree changes share the informational-warning allowlist between
forecasts and alerts and add one regression test, bringing the suite to 78 tests.
**The 78-test result is pending CI**, not part of the verified run above. The new
five-second packaged-process smoke check and upload-artifact v5 update also await
a green run. There has been no interactive real-Mac validation.

## Runner Selection

Verified against official sources on **2026-09-07**:

- The [runner-images available-images table](https://github.com/actions/runner-images#available-images)
  lists `macos-26` as the standard macOS 26 **arm64** hosted runner. The similarly
  named Intel image documentation is not the reference for this label.
- The [arm64 image inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
  lists `/Applications/Xcode_26.0.1.app` with macOS 26.0 SDK. CI selects that
  installed version explicitly through `DEVELOPER_DIR` rather than relying on the
  image's newer default Xcode.
- CI logs OS, architecture, Xcode, Swift, SDK version, and SDK path, and fails unless
  the host OS and SDK are 26+ and the selected Xcode is 26.x. If the installed path
  is removed, update it from the official inventory; do not silently downgrade.
- Linux uses `ubuntu-24.04` with the official `swift:6.2-noble` container and installs
  `libsqlite3-dev` plus `pkg-config` using apt. The
  [official image manifest](https://github.com/docker-library/official-images/blob/master/library/swift)
  lists the Swift 6.2 Ubuntu 24.04 image for amd64 and arm64. The
  [Docker Hub tag API](https://hub.docker.com/v2/repositories/library/swift/tags/6.2-noble)
  confirmed an active image; the workflow pins its multi-platform index digest,
  `sha256:29b983751c605c2d3102d2ab93438c6e0cadf110d9d2aa6e929b6dec9dcb7cbc`.

Image inventories change and runner capacity or repository policy can still block
a job. The version checks intentionally fail rather than imply validation on a
different platform. The artifact is arm64, not a universal macOS build.

## Action Provenance

Full commit references were resolved from GitHub's API using `gh`, not copied from
an unverified example:

| Action | Queried ref | Verified commit |
| --- | --- | --- |
| `actions/checkout` | `v5` | `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` |
| `actions/upload-artifact` | `v5` | `330a01c490aca151604b8cf639adc76d48f6c5d4` |

To review future updates:

```bash
gh api repos/actions/checkout/commits/v5 --jq .sha
gh api repos/actions/upload-artifact/commits/v5 --jq .sha
```

Checkout was updated to this verified v5 commit to avoid its Node 20 deprecation
warning; the pinned action declares `runs.using: node24`. The upload-artifact v5
commit was separately verified through `gh`; its pinned `action.yml` still declares
`runs.using: node20`, so a v5 label alone does not establish a Node 24 migration.

Tags can move; review the upstream changes before replacing a pin. Container
digest pins also need deliberate updates to receive toolchain and OS fixes.

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

The pending smoke step starts `dist/TokenBudget.app/Contents/MacOS/TokenBudget`,
waits five seconds, checks process existence with `kill -0`, and terminates it on
step exit. This catches immediate process exits, not broken UI, settings, imports,
permissions, or notification delivery. It was not present in the verified run.

A passing ad-hoc signature check is an integrity check, not Developer ID signing,
notarization, a Gatekeeper assessment, or proof the app works interactively.
Interactive validation and production distribution remain open work.
