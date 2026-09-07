#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
    printf '%s\n' 'Token Budget requires macOS 26+ and a macOS 26 SDK.' >&2
    exit 1
fi

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export MACOSX_DEPLOYMENT_TARGET=26.0
swift build --package-path "$ROOT" --configuration release --product TokenBudget
BIN_PATH="$(swift build --package-path "$ROOT" --configuration release --show-bin-path)"
APP="$ROOT/dist/TokenBudget.app"

mkdir -p "$APP/Contents/MacOS"
install -m 755 "$BIN_PATH/TokenBudget" "$APP/Contents/MacOS/TokenBudget"
install -m 644 "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
printf 'Built locally, ad-hoc signed (not notarized): %s\n' "$APP"
printf '%s\n' 'Launch with Finder or open the app. Gatekeeper settings have not been changed.'
