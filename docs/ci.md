# CI Environment

The workflow is configured to test portable logic on Linux and test, build,
package, and verify a development app on macOS. It does not launch the UI or
replace interactive real-Mac validation.

## Validation Snapshot

Reported on **2026-09-07**: 76 portable tests passed locally, and macOS CI
compilation passed. All adapter tests in that macOS run were skipped due to a
path-symlink bug. A fix is in progress; adapter validation requires a rerun in which
the tests actually execute. Compilation success is not a passing native adapter
suite, and does not establish that subsequent source changes have been compiled.

Native packaging, code-signature verification, and artifact creation are **not yet
confirmed**. There has been no interactive real-Mac validation. These results are
a reported snapshot, not a new test run performed for this documentation update.

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
| `actions/upload-artifact` | `v4` | `ea165f8d65b6e75b540449e92b4886f43607fa02` |

To review future updates:

```bash
gh api repos/actions/checkout/commits/v5 --jq .sha
gh api repos/actions/upload-artifact/commits/v4 --jq .sha
```

Checkout was updated to this verified v5 commit to avoid its Node 20 deprecation
warning; the pinned action declares `runs.using: node24`. This does not imply that
every other action uses Node 24: the upload-artifact pin remains unchanged.

Tags can move; review the upstream changes before replacing a pin. Container
digest pins also need deliberate updates to receive toolchain and OS fixes.

## Permissions and Artifacts

Only `contents: read` is granted, checkout does not persist credentials, and there
is no `pull_request_target`, secret-dependent signing, release publishing, or
write permission. Pull requests run on hosted disposable runners. No real usage
fixtures or private logs belong in CI.

The packaging contract is `bash scripts/build-app.sh` producing
`dist/TokenBudget.app`. The script targets this path, but successful bundle creation
and verification still need a native run.

The workflow requires the bundle and verifies it with
`codesign --verify --deep --strict`; it does not re-sign an invalid bundle to hide
a packaging failure. `ditto` creates a ZIP preserving bundle metadata before
upload. Only that ZIP is uploaded, with seven-day retention, not the workspace,
test logs, or a user's local data.

A passing ad-hoc signature check is an integrity check, not Developer ID signing,
notarization, a Gatekeeper assessment, or proof the app launches. Native execution
and distribution remain validation gaps until separately demonstrated.
