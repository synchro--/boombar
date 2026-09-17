#!/usr/bin/env bash
#
# Build a release DMG and ZIP for BoomBar.
#
# Usage:
#   scripts/release.sh <version> [--universal] [--publish]
#
#   <version>      semantic version, e.g. 1.0.0 (no leading "v")
#   --universal    build arm64 + x86_64 (requires full Xcode)
#   --publish      create/update the GitHub release v<version> and upload assets
#
# Environment:
#   CODESIGN_IDENTITY   Developer ID Application identity (default: ad-hoc "-")
#   VERSION             overrides <version> if set
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BoomBar"
DISPLAY_NAME="Boom Bar"
DIST="$ROOT/dist"
UNIVERSAL=0
PUBLISH=0
VERSION_ARG=""

for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --publish) PUBLISH=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) VERSION_ARG="$arg" ;;
  esac
done

VERSION="${VERSION:-${VERSION_ARG:-$(tr -d '[:space:]' < "$ROOT/VERSION")}}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$ ]]; then
  echo "invalid version: $VERSION" >&2
  exit 2
fi
export VERSION

BUILD_ARGS=(release)
if [[ "$UNIVERSAL" == "1" ]]; then
  BUILD_ARGS+=(--universal)
  echo "==> Building Boom Bar $VERSION (universal)"
else
  echo "==> Building Boom Bar $VERSION"
fi
"$ROOT/scripts/build-app.sh" "${BUILD_ARGS[@]}"

APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

echo "==> Creating DMG"
STAGE="$DIST/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> Creating ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Checksums (sha256)"
shasum -a 256 "$DMG" "$ZIP"

if [[ "$PUBLISH" == "1" ]]; then
  echo "==> Publishing GitHub release v$VERSION"
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$DMG" "$ZIP" --clobber
  else
    gh release create "v$VERSION" "$DMG" "$ZIP" \
      --title "Boom Bar $VERSION" --generate-notes
  fi
fi

echo "==> Done"
echo "    $DMG"
echo "    $ZIP"
