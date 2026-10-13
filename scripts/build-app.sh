#!/usr/bin/env bash
#
# Assemble a double-clickable BoomBar.app from the SwiftPM build product.
#
# Usage:
#   scripts/build-app.sh [debug|release] [--universal] [--dev]
#
# Produces dist/BoomBar.app and ad-hoc codesigns it (unless CODESIGN_IDENTITY
# is set, in which case that identity is used).
#
# --dev builds dist/BoomBar Dev.app with bundle id com.synchro.boombar.dev so it
# can run side by side with the released app (separate prefs domain, separate
# Bluetooth permission grant).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BoomBar"
EXECUTABLE_NAME="BoomBar"
BUNDLE_NAME="BoomBar"
DISPLAY_NAME="Boom Bar"
BUNDLE_ID="com.synchro.boombar"
CONFIG="release"
UNIVERSAL=0

for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --universal) UNIVERSAL=1 ;;
    --dev)
      EXECUTABLE_NAME="BoomBarDev"
      BUNDLE_NAME="BoomBar Dev"
      DISPLAY_NAME="Boom Bar Dev"
      BUNDLE_ID="com.synchro.boombar.dev"
      ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

ARCH_LABEL=""
[[ "$UNIVERSAL" == "1" ]] && ARCH_LABEL=" (universal)"
echo "==> Building ($CONFIG$ARCH_LABEL)"
if [[ "$UNIVERSAL" == "1" ]]; then
  swift build -c "$CONFIG" --package-path "$ROOT" --arch arm64 --arch x86_64
  BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --arch arm64 --arch x86_64 --show-bin-path)"
else
  swift build -c "$CONFIG" --package-path "$ROOT"
  BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"
fi

BIN="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN" ]]; then
  echo "build product not found: $BIN" >&2
  exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/$BUNDLE_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  -c "Set :CFBundleDisplayName $DISPLAY_NAME" \
  -c "Set :CFBundleName $BUNDLE_NAME" \
  -c "Set :CFBundleIdentifier $BUNDLE_ID" \
  -c "Set :CFBundleExecutable $EXECUTABLE_NAME" "$APP/Contents/Info.plist"

echo "==> Verifying Info.plist ($DISPLAY_NAME v$VERSION build $BUILD_NUMBER, $BUNDLE_ID)"
plutil -lint "$APP/Contents/Info.plist"

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "==> Codesigning with identity: $IDENTITY"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - --entitlements "$ROOT/Resources/BoomBar.entitlements" "$APP"
else
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Resources/BoomBar.entitlements" \
    --sign "$IDENTITY" "$APP"
fi

echo "==> Built $APP"
