# Distributing BoomBar

BoomBar is a menu-bar-only (`LSUIElement`) macOS app with no sandbox
requirement today. This document covers building, signing, notarizing, and
packaging it for distribution, from local development through Homebrew.

---

## 1. Local development

```bash
swift build                 # debug
swift run                   # run the menu-bar app from source
scripts/build-app.sh debug  # assemble dist/BoomBar.app (ad-hoc signed)
```

`swift run` produces a bare Mach-O executable, not a bundle. macOS attributes
Bluetooth (TCC) permission to the **terminal** that launched it, and desktop
notifications may be unavailable. The `.app` bundle produced by
`scripts/build-app.sh` has a `CFBundleIdentifier` and its own permission identity.

## 2. Release build (universal)

```bash
swift build -c release --arch arm64 --arch x86_64
```

SwiftPM emits a universal binary at
`$(swift build -c release --show-bin-path)/BoomBar`. The helper script
accepts the same flags:

```bash
scripts/build-app.sh release --universal
```

> Note: multi-architecture SwiftPM builds are routed through `xcbuild`, so a
> full Xcode installation (`xcode-select -s /Applications/Xcode.app`) is
> required. With only the Command Line Tools installed, build the host
> architecture (`swift build -c release`) instead.

The script:

1. builds the requested configuration (optionally universal),
2. creates `dist/BoomBar.app/Contents/{MacOS,Resources}`,
3. copies the binary and `Resources/Info.plist`,
4. validates the plist with `plutil -lint`,
5. codesigns the bundle with `Resources/BoomBar.entitlements`.

## 3. Code signing

Ad-hoc signing (`codesign --sign -`) is fine for local use but is **not**
distributable: Gatekeeper will quarantine it on other Macs.

For distribution, use a **Developer ID Application** certificate and the
hardened runtime:

```bash
BUNDLE=dist/BoomBar.app
IDENTITY="Developer ID Application: Your Name (TEAMID)"

codesign --force --options runtime --timestamp \
  --entitlements Resources/BoomBar.entitlements \
  --sign "$IDENTITY" "$BUNDLE"

codesign --verify --deep --strict --verbose=2 "$BUNDLE"
```

Set `CODESIGN_IDENTITY` to that identity and `scripts/build-app.sh` will use the
hardened-runtime path automatically:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  scripts/build-app.sh release --universal
```

Entitlements (`Resources/BoomBar.entitlements`):

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

This entitlement is required for the App Sandbox; for a non-sandboxed Developer
ID build it is inert but harmless, and keeps the door open for sandboxing. If you
enable the sandbox, note section 8.

> Tip: sign nested/embedded content first if you ever add frameworks or an
> updater. For the current single-binary app, signing the `.app` is sufficient.

## 4. Notarization

Notarization requires a Developer ID signature and an Apple credential.

```bash
# Store credentials once (app-specific password recommended)
xcrun notarytool store-credentials "BoomBar-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"

# Or use an App Store Connect API key: --key AuthKey_XXX.p8 --key-id XXX --issuer UUID

# Zip the app (notarytool wants an archive) and submit
ditto -c -k --keepParent dist/BoomBar.app dist/BoomBar.zip
xcrun notarytool submit dist/BoomBar.zip \
  --keychain-profile "BoomBar-notary" --wait

# Staple the ticket and verify
xcrun stapler staple dist/BoomBar.app
xcrun stapler validate dist/BoomBar.app
spctl -a -vv --type execute dist/BoomBar.app
```

After stapling, re-zip or package the stapled `.app` for upload so the ticket
travels with the download.

## 5. Packaging

**Zip** (simplest):

```bash
ditto -c -k --keepParent dist/BoomBar.app dist/BoomBar-1.0.0.zip
```

**DMG** (nicer UX). Either `create-dmg`:

```bash
brew install create-dmg
create-dmg \
  --volname "BoomBar" \
  --app-drop-link 600 185 \
  --icon "BoomBar.app" 180 185 \
  dist/BoomBar-1.0.0.dmg dist/BoomBar.app
```

or plain `hdiutil`:

```bash
mkdir -p dist/dmg-root
cp -R dist/BoomBar.app dist/dmg-root/
ln -s /Applications dist/dmg-root/Applications
hdiutil create -volname BoomBar -srcfolder dist/dmg-root \
  -ov -format UDZO dist/BoomBar-1.0.0.dmg
codesign --force --timestamp --sign "$IDENTITY" dist/BoomBar-1.0.0.dmg
```

### No-Apple-account fallback

Ad-hoc signed builds are uploaded by `scripts/release.sh` under both versioned
and stable names (`BoomBar-<version>.dmg` and `BoomBar.dmg`), so
`.../releases/latest/download/BoomBar.dmg` always resolves.

Because the build is not notarized, Gatekeeper blocks it **when the download
carries the quarantine attribute** (browser downloads do):

```bash
xattr -dr com.apple.quarantine /Applications/BoomBar.app
```

On macOS 15 and later the old Control-click → **Open** shortcut no longer
applies; users must use **System Settings → Privacy & Security → Open Anyway**.

To avoid the prompt entirely, install with `install.sh`, which fetches the DMG
with `curl` (no quarantine attribute) and clears the flag explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/synchro--/boombar/main/install.sh | bash
```

This is a workaround, not a fix — signing + notarization (sections 3–4) is the
only way to remove the warning for all download paths.

## 6. Homebrew Cask

Homebrew Cask is shipped via a self-hosted tap:
<https://github.com/synchro--/homebrew-boombar> (`Casks/boombar.rb`).

```bash
brew tap synchro--/boombar
brew trust synchro--/boombar   # Homebrew 7 refuses casks from untrusted taps
brew install --cask boombar
```

Two current constraints:

- **The official `homebrew/cask` tap is not an option.** It requires artefacts
  to pass Gatekeeper checks (signed + notarized) and Homebrew is dropping casks
  that fail those checks. The ad-hoc build is therefore ineligible.
- **The cask still leaves the app quarantined** (Homebrew quarantines downloads;
  the `--no-quarantine` flag has been removed). So the cask provides
  `brew upgrade` management but does **not** remove the one-time Gatekeeper
  step — the cask `caveats` point users at Open Anyway / `xattr` and at
  `install.sh` for a warning-free install. Avoid a quarantine-stripping
  `postflight`: it silently bypasses Gatekeeper and is discouraged.

The `version`/`sha256` in the cask must be bumped each release (the DMG is
version-pinned). `brew audit --cask --online boombar` and `brew style` should
pass before updating the tap.

## 7. Auto-update with Sparkle

1. Add [Sparkle](https://sparkle-project.org/) as a SwiftPM dependency
   (`https://github.com/sparkle-project/Sparkle`).
2. Generate an EdDSA key pair with `generate_keys`; keep the private key secret
   and put the public key in `Info.plist` as `SUPublicEDKey`.
3. Add `SUFeedURL` pointing at an appcast XML, plus an `SUEnableAutomaticChecks`
   key, and embed `Sparkle.framework` in `Contents/Frameworks` (signing it
   inside-out before the app).
4. Publish a signed appcast entry per release and let Sparkle handle updates.

Sparkle requires the framework to be code signed with the same identity and
hardened runtime; see its documentation for the exact embedding steps.

## 8. Mac App Store caveat

The App Sandbox changes what is possible:

- **Bluetooth LE** is allowed with `com.apple.security.device.bluetooth`, so
  power **ON** (BLE GATT) and **battery** reads would work.
- **Classic RFCOMM** (used for power **OFF**, and the fallback for audio
  reconnect) is **not** available inside the sandbox. There is no public
  sandbox-safe API for opening an RFCOMM channel to an arbitrary paired device.

Consequently a Mac App Store build would likely be **ON-only / feature-limited**.
Because the app's headline feature is turning the speaker *off*, the recommended
primary channel is **Developer ID + notarization** (sections 3–5), not the MAS.

## 9. GitHub Actions release workflow

Sketch — build a universal binary, sign, notarize, staple, package a DMG and
ZIP, and attach them to the GitHub release:

```yaml
name: Release

on:
  push:
    tags: ["v*"]

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode.app

      - name: Import signing certificate
        env:
          CERT_P12: ${{ secrets.MACOS_CERT_P12 }}
          CERT_PASSWORD: ${{ secrets.MACOS_CERT_PASSWORD }}
        run: |
          echo "$CERT_P12" | base64 --decode > cert.p12
          security create-keychain -p actions build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p actions build.keychain
          security import cert.p12 -k build.keychain -P "$CERT_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k actions build.keychain

      - name: Store notary credentials
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          TEAM_ID: ${{ secrets.TEAM_ID }}
          APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: |
          xcrun notarytool store-credentials "ci-notary" \
            --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD"

      - name: Build, sign, notarize
        env:
          CODESIGN_IDENTITY: ${{ secrets.CODESIGN_IDENTITY }}
          VERSION: ${{ github.ref_name }}
        run: |
          scripts/build-app.sh release --universal
          ditto -c -k --keepParent dist/BoomBar.app dist/BoomBar.zip
          xcrun notarytool submit dist/BoomBar.zip --keychain-profile ci-notary --wait
          xcrun stapler staple dist/BoomBar.app
          spctl -a -vv --type execute dist/BoomBar.app
          ditto -c -k --keepParent dist/BoomBar.app "dist/BoomBar-${VERSION}.zip"
          # create DMG here (create-dmg/hdiutil), then sign it

      - uses: softprops/action-gh-release@v2
        with:
          files: |
            dist/*.zip
            dist/*.dmg
```

Store `MACOS_CERT_P12` (base64 of the exported `.p12`), its password,
`APPLE_ID`, `TEAM_ID`, `APPLE_APP_PASSWORD`, and `CODESIGN_IDENTITY` as encrypted
repository secrets. Never commit certificates or passwords.
