#!/usr/bin/env bash
#
# Install Boom Bar from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/synchro--/boombar/main/install.sh | bash
#
# Options (when run locally):
#   --dest DIR    install to DIR instead of /Applications
#   --no-launch   do not open the app after installing
#   --version X.Y.Z   install a specific version instead of the latest
#
# The app is ad-hoc signed. Files downloaded with curl do not receive the
# quarantine attribute, so no Gatekeeper prompt appears. The quarantine flag is
# also cleared explicitly as a safety net.
#
set -euo pipefail

REPO="synchro--/boombar"
APP_NAME="BoomBar"
DISPLAY_NAME="Boom Bar"
VERSION="latest"
DEST="/Applications"
LAUNCH=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --no-launch) LAUNCH=0; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) echo "unexpected argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "$VERSION" == "latest" ]]; then
  URL="https://github.com/$REPO/releases/latest/download/BoomBar.dmg"
else
  URL="https://github.com/$REPO/releases/download/v$VERSION/BoomBar-$VERSION.dmg"
fi

TMP="$(mktemp -d)"
MOUNT="$TMP/mnt"
cleanup() {
  hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "==> Downloading $DISPLAY_NAME"
mkdir -p "$MOUNT"
curl -fL --progress-bar "$URL" -o "$TMP/BoomBar.dmg"

echo "==> Mounting disk image"
hdiutil attach "$TMP/BoomBar.dmg" -nobrowse -mountpoint "$MOUNT" >/dev/null

TARGET="$DEST/$APP_NAME.app"
echo "==> Installing to $TARGET"
rm -rf "$TARGET"
mkdir -p "$DEST"
cp -R "$MOUNT/$APP_NAME.app" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "==> Installed $DISPLAY_NAME"
if [[ "$LAUNCH" == "1" ]]; then
  echo "==> Launching (grant Bluetooth when asked; look for the speaker icon in the menu bar)"
  open "$TARGET"
fi
