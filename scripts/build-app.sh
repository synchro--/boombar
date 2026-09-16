#!/usr/bin/env bash
#
# Assemble a double-clickable MegaBoomBar.app from the SwiftPM build product.
#
# Usage:
#   scripts/build-app.sh [debug|release] [--universal]
#
# Produces dist/MegaBoomBar.app and ad-hoc codesigns it (unless CODESIGN_IDENTITY
# is set, in which case that identity is used).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MegaBoomBar"
CONFIG="release"
UNIVERSAL=0

for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --universal) UNIVERSAL=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

ARCH_LABEL=""
[[ "$UNIVERSAL" == "1" ]] && ARCH_LABEL=" (universal)"
echo "==> Building ($CONFIG$ARCH_LABEL)"
if [[ "$UNIVERSAL" == "1" ]]; then
  swift build -c "$CONFIG" --package-path "$ROOT" --arch arm64 --arch x86_64
else
  swift build -c "$CONFIG" --package-path "$ROOT"
fi

BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN" ]]; then
  echo "build product not found: $BIN" >&2
  exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Verifying Info.plist"
plutil -lint "$APP/Contents/Info.plist"

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "==> Codesigning with identity: $IDENTITY"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - --entitlements "$ROOT/Resources/MegaBoomBar.entitlements" "$APP"
else
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Resources/MegaBoomBar.entitlements" \
    --sign "$IDENTITY" "$APP"
fi

echo "==> Built $APP"
