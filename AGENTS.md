# AGENTS.md — Boom Bar

Menu-bar macOS app to control Ultimate Ears BOOM-family speakers (power on/off,
battery, audio connect). Native Swift port of the hardware-verified Python
reference at `../ue-megaboom` (do not modify that repo from here).

## Naming (decided)

| Thing | Value |
|---|---|
| Display name (`CFBundleDisplayName`) | `Boom Bar` (with space) |
| Product / target / executable / `CFBundleName` | `BoomBar` (no space) |
| Repo / directory | `boombar` (currently `megaboom-bar` until Phase A) |
| Bundle identifier | `com.synchro.boombar` |
| License | MIT |
| GitHub | `synchro--/boombar` (public) |

## Current status

- [x] Basic native app implemented and building (`swift build`, `swift run`).
- [x] BLE power ON, RFCOMM power OFF, battery read, audio reconnect, menu-bar UI.
- [ ] **Phases A–F below (in progress — start at Phase A).**

Last updated: see git log. Next action: **Phase A — rename/restructure.**

## Roadmap

### Phase A — Rename & restructure (preserve git history)
- [ ] `git mv /Users/rain/hub/megaboom-bar /Users/rain/hub/boombar`
- [ ] Rename Swift target/product/module `MegaBoomBar` → `BoomBar` (`Package.swift`, `Sources/BoomBar/`)
- [ ] `Resources/Info.plist`: `CFBundleDisplayName="Boom Bar"`,
      `CFBundleName/CFBundleExecutable="BoomBar"`, `CFBundleIdentifier="com.synchro.boombar"`
- [ ] Update `scripts/build-app.sh`, entitlements filename, `docs/DISTRIBUTION.md`, `README.md`
- [ ] UserDefaults prefix `MegaBoomBar.` → `BoomBar.`

### Phase B — Protocol generalization (all BOOM-family models)
- [ ] Model-profile table: name hints, advert service UUIDs (`FE61`, `FE9F`),
      power characteristic UUIDs (`C6D6DC0D-…`, `69C0F621-…`)
- [ ] **OFF over BLE primary**: write `hostMAC + 0x02` to `C6D6DC0D-…`;
      keep classic RFCOMM `02 01 B6` (channel 1) as fallback
- [ ] Read `2A00` (device name) + `2A24` (model number) on connect
- [ ] Use `retrievePeripherals(withIdentifiers:)` with cached id so BLE works
      when the speaker is on / not advertising
- [ ] "Supported speakers" table in README + model-report issue template

### Phase C — Packaging polish
- [ ] `Resources/AppIcon.icns` (Material Symbols speaker-derived, attributed) + `CFBundleIconFile`
- [ ] Single version source (`VERSION`) injected into the bundle; remove hardcoded `1.0.0`
- [ ] `LICENSE` (MIT) and README **Install** section

### Phase D — Release tooling
- [ ] `scripts/release.sh <version> [--universal]`: build → assemble → sign
      (ad-hoc default / Developer ID via `CODESIGN_IDENTITY`) → DMG (`hdiutil`
      + `/Applications` symlink) → ZIP → SHA-256 → optional `gh release create`

### Phase E — GitHub + universal CI
- [ ] `gh repo create synchro--/boombar --public` and push
- [ ] `.github/workflows/release.yml` on tag `v*`, runner `macos-14`:
      universal `arm64+x86_64` build → ad-hoc sign → DMG + ZIP → attach to Release
      (no secrets needed for the free/ad-hoc path)

### Phase F — Verify & publish
- [ ] Local: ON, OFF (BLE first, RFCOMM fallback), battery, reconnect on MEGABOOM 3
- [ ] CI: tag `v1.0.0`, download artifact, `lipo -info` shows both arches, mount DMG, launch
- [ ] Release notes: one-time Gatekeeper step (right-click → Open) + supported-models table

## Distribution decisions

- No paid Apple Developer account → **ad-hoc signed** builds; recipients do a
  one-time right-click → Open (or `xattr -dr com.apple.quarantine`). Notarization
  can be added later via `CODESIGN_IDENTITY` + `notarytool` (see `docs/DISTRIBUTION.md`).
- Universal binary is built in **CI only** — this Mac has Command Line Tools
  without full Xcode, so `--arch x86_64` fails locally.
- Mac App Store is not planned (sandbox blocks classic RFCOMM; the BLE-only OFF
  path may change this later).

## Protocol facts (reverse-engineered, verified on MEGABOOM 3)

- Power ON: BLE GATT write to `C6D6DC0D-07F5-47EF-9B59-630622B01FD3`
  (fallback `69C0F621-1354-4CF8-98A6-328B8FAA1897`), payload = **this Mac's BT
  MAC (6 bytes, display order) + `0x01`**. Only works in BLE standby and only
  for paired hosts. Reversed-MAC payload is a fallback.
- Power OFF: BLE write of `MAC + 0x02` to the same characteristic (primary);
  classic RFCOMM channel 1 payload `02 01 B6` (fallback). A stale ACL link makes
  RFCOMM fail with `kIOReturnError` — close/reopen the connection and retry once.
- Battery: BLE `00002A19-0000-1000-8000-00805F9B34FB` (uint8 percent).
- Speaker discovery: name hints (`UE `, `BOOM`, `MEGABOOM`, `HYPERBOOM`,
  `EPICBOOM`, `EVERBOOM`) or advert service UUID `FE61`/`FE9F` (Logitech mfr id 224).
- Host MAC: `IOBluetoothHostController.default()?.addressAsString()`, else parse
  `system_profiler SPBluetoothDataType -json` (`controller_address`).
- Prerequisites: speaker paired once with this Mac and Bluetooth Standby /
  Remote Activation enabled.

## Build & run

```bash
swift build                         # debug
swift run                           # menu-bar app from source
scripts/build-app.sh release        # assemble dist/BoomBar.app (ad-hoc signed)
```

If a build fails with a module-cache path error after moving/renaming the
directory: `rm -rf .build && swift build`.

## Conventions

- AppKit `NSStatusItem` menu-bar app, `LSUIElement` (no dock icon).
- Blocking Bluetooth work runs off the CoreBluetooth callback queue on a worker
  queue; UI updates marshalled to main; coordinate with semaphores.
- No comments unless they add real value; keep names descriptive.
- `docs/DISTRIBUTION.md` is the authoritative signing/notarization reference.

## Known risks

- Only MEGABOOM 3 is hardware-verified; other models inferred from the official
  app's support list and shared GATT UUIDs (BOOM 2 matches). Provide a
  supported-models table and a model-report path.
- BLE-OFF may fail while the speaker is on/connected → RFCOMM fallback covers it.
