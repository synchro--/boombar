# BoomBar

[![CI](https://github.com/synchro--/boombar/actions/workflows/ci.yml/badge.svg)](https://github.com/synchro--/boombar/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/synchro--/boombar?label=release)](https://github.com/synchro--/boombar/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/synchro--/boombar/blob/main/LICENSE)

**Your speaker, one click away.**

BoomBar turns Ultimate Ears BOOM-family speakers on and off and shows their
battery level in the macOS menu bar — no phone, no UE app, no reaching behind
the speaker.

The official UE | BOOM app can do this on iOS and Android. BoomBar brings the
useful part to the Mac. Tiny native menu-bar app: no Dock icon, no account, no
background service, and it never sits in your audio path.

Works with the [UE BOOM family](#supported-speakers): MEGABOOM 3 is
hardware-verified; the rest are expected to work.

## Install

**Homebrew**

```bash
brew tap synchro--/boombar
brew trust synchro--/boombar
brew install --cask boombar
```

**[Installer](https://raw.githubusercontent.com/synchro--/boombar/main/install.sh)** — no Gatekeeper prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/synchro--/boombar/main/install.sh | bash
```

**DMG** — download the [latest release](https://github.com/synchro--/boombar/releases/latest/download/BoomBar.dmg)
and drag **Boom Bar** into **Applications**.

BoomBar is ad-hoc signed, not notarized. If macOS blocks the first launch, open
**System Settings → Privacy & Security → Open Anyway**, or run:

```bash
xattr -dr com.apple.quarantine "/Applications/BoomBar.app"
```

Grant Bluetooth when asked. The app lives in the menu bar, not the Dock.

## What it does

- **Power** — turn the speaker on from standby or shut it down.
- **Battery** — see the charge in the menu; refresh it any time.
- **Audio** — reconnect the classic audio link.
- **Volume re-sync** — fix AVRCP volume desync with one click.
- **Default output** — optionally route audio to the speaker on power-on or reconnect.

No volume slider. No EQ. No audio driver. Just the controls macOS and UE never
gave you.

## Specs

### Supported speakers

| Model | Status |
|---|---|
| MEGABOOM 3 | Verified |
| BOOM 2 / 3 / 4, MEGABOOM / 4 | Expected |
| HYPERBOOM, EPICBOOM, EVERBOOM | Expected |
| BOOM 1, MEGABOOM 1 | Likely |
| ROLL / ROLL 2 / ROLL 3 | Untested |
| WONDERBOOM, MINIROLL | Not supported |
| BLAST / MEGABLAST | Not supported |

Only the MEGABOOM 3 has been hardware-verified. If your model is missing or
doesn't work, [open a model report](https://github.com/synchro--/boombar/issues/new?template=model-report.md)
with the model and which actions work. The app finds your paired speaker
automatically; there is no Scan menu item.

### Requirements

- macOS 13 or later (developed on macOS 26, Apple Silicon)
- Speaker paired once with this Mac
- Bluetooth Standby / Remote Activation enabled (the default)
- Optional: [`blueutil`](https://github.com/toy/blueutil) for reliable audio reconnection
- Optional: [`SwitchAudioSource`](https://github.com/deweller/switchaudio-osx) for default-output switching

### Menu reference

- **Connected: `<name>` / Off / standby** — current state.
- **Turn On / Turn Off** — switches with the connection state.
- **Connect Audio** — reconnects the classic audio profile.
- **Re-sync Volume** — drops and re-establishes the classic link when AVRCP
  volume sync drops. Playback pauses during the re-link; press play to resume.
- **Battery: `n%`** — click to refresh over BLE. Idle auto-refresh every 5
  minutes; paused during playback so it doesn't knock volume out of sync.
- **Auto-set as Default Output** — when on, Turn On / Connect Audio also route
  the default output to the speaker via `SwitchAudioSource`.
- **BoomBar `<version>`** — version footer.
- **Quit**.

All Bluetooth work runs off the main thread.

### How it works

The speaker exposes a BLE control characteristic for both directions, with a
classic-Bluetooth fallback:

- **On** — write this Mac's Bluetooth address + `0x01` to the standby control
  characteristic (`C6D6DC0D-07F5-47EF-9B59-630622B01FD3`, fallback
  `69C0F621-1354-4CF8-98A6-328B8FAA1897`). If that fails, the byte-reversed
  address is retried. Only works in BLE standby, for previously paired hosts.
- **Off** — write the address + `0x02`. If the speaker stays connected, fall
  back to classic RFCOMM/SPP channel 1 with `02 01 B6`.

Because the payload contains your Mac's Bluetooth address, pair the speaker once
first, with Bluetooth Standby / Remote Activation enabled.

### Build and run

```bash
swift build && swift run          # development
scripts/build-app.sh release      # double-clickable, ad-hoc signed .app
open dist/BoomBar.app
```

For a universal release binary:

```bash
swift build -c release --arch arm64 --arch x86_64
```

`swift run` has no app bundle, so macOS attributes Bluetooth permission to your
terminal. Use the built `.app` for a proper identity and permission prompt.

### Configuration

Settings live in `UserDefaults` (`com.synchro.boombar`) under the `BoomBar.`
prefix:

- `hostMAC` — this Mac's Bluetooth address (auto-detected).
- `speakerMAC` / `speakerName` / `speakerModel` — paired speaker details.
- `peripheralIdentifier` — cached CoreBluetooth identifier for faster battery
  reads and BLE control while the speaker isn't advertising.
- `payloadHex` — optional raw wake-payload override.
- `setAsDefaultOutput` — menu checkbox state.

### Protocol notes

- Discovery uses BLE service UUIDs `FE61` / `FE9F`, name hints (`UE `, `BOOM`,
  `MEGABOOM`, `HYPERBOOM`, `EPICBOOM`, `EVERBOOM`), and Logitech manufacturer id
  `224`.
- Battery is the standard GATT characteristic
  `00002A19-0000-1000-8000-00805F9B34FB` (uint8 percent).
- The standby control characteristic only exists while the speaker is off; its
  absence means "already on".
- A stale ACL link can make RFCOMM fail with `kIOReturnError` (`0xE00002BC`);
  the app drops the classic connection, reopens it, and retries.

### Packaging

Signed release builds, DMG/ZIP packaging, and the notarization path are covered
in [docs/DISTRIBUTION.md](https://github.com/synchro--/boombar/blob/main/docs/DISTRIBUTION.md).

### Disclaimer

Reverse-engineered behaviour, not an official Ultimate Ears API. Results may
vary by speaker generation and firmware.

## License

[MIT](https://github.com/synchro--/boombar/blob/main/LICENSE) © 2026 BoomBar
contributors.
