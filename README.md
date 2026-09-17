# BoomBar

Turn Ultimate Ears BOOM-family speakers on and off from the macOS menu bar, and
read their battery level. A native Swift port of
[`ue-megaboom`](../ue-megaboom).

The official UE | BOOM app can power your speaker on remotely, but it only runs
on iOS and Android. This is a small macOS client that speaks the same
reverse-engineered Bluetooth protocol. It targets the whole BOOM family — BOOM,
MEGABOOM, HYPERBOOM, EPICBOOM and EVERBOOM.

## How it works

The speaker exposes a BLE control characteristic for both directions, with a
classic-Bluetooth fallback:

- **on** — Bluetooth LE GATT write to the speaker's standby control
  characteristic (`C6D6DC0D-07F5-47EF-9B59-630622B01FD3`, fallback
  `69C0F621-1354-4CF8-98A6-328B8FAA1897`). The payload is this Mac's Bluetooth
  address in display order followed by `0x01`; if that fails the byte-reversed
  address is retried. Only works while the speaker is in BLE standby, and only
  for hosts it has previously been paired with.
- **off** — the same BLE characteristic with this Mac's address followed by
  `0x02`. If the speaker is still connected afterwards, the app falls back to
  classic Bluetooth RFCOMM/SPP on channel 1, sending `02 01 B6`.

Because the payload contains your Mac's Bluetooth address, the speaker must have
been paired with this Mac once before, with Bluetooth Standby / Remote
Activation enabled (the default).

## Supported speakers

| Model | Power on/off | Status |
|---|---|---|
| MEGABOOM 3 | BLE `MAC+01` / BLE `MAC+02` | Verified |
| BOOM 2 / 3 / 4, MEGABOOM / 4 | Same protocol (official app supports remote on/off) | Expected |
| HYPERBOOM, EPICBOOM, EVERBOOM | Same app/protocol ("Remote Activation Mode") | Expected |
| BOOM 1, MEGABOOM 1 | Older app "Remote On/Off" | Likely |
| ROLL / ROLL 2 / ROLL 3 | Community reports the technique works | Untested |
| WONDERBOOM, MINIROLL | No app, no remote mode | Not supported |
| BLAST / MEGABLAST | Separate app/ecosystem | Not supported |

Only the MEGABOOM 3 has been hardware-verified. If your model isn't listed (or
doesn't work), please open a **model report** issue with the output of
`swift run` → Scan, plus the advertised service UUIDs and whether each action
works.

## Requirements

- macOS 13 or later (developed on macOS 26, Apple Silicon)
- Swift 5.9+ toolchain (`/usr/bin/swift`)
- The speaker must be paired with this Mac
- Optional: [`blueutil`](https://github.com/toy/blueutil) (`brew install blueutil`)
  for reliable audio reconnection
- Optional: [`SwitchAudioSource`](https://github.com/ruddfawcett/switchaudio-osx)
  (`brew install switchaudio-osx`) to switch the default audio output

## Build and run

```bash
# development: build and run the menu-bar app as a plain executable
swift build
swift run

# universal release binary
swift build -c release --arch arm64 --arch x86_64

# assemble a double-clickable, ad-hoc codesigned .app
scripts/build-app.sh release
open dist/BoomBar.app
```

When run with `swift run` there is no app bundle, so macOS attributes the
Bluetooth permission to the launching terminal. Launch the built
`dist/BoomBar.app` to get a proper app identity and permission prompt.

The first time the app needs Bluetooth it will ask for permission. If you deny
it, re-enable it in System Settings → Privacy & Security → Bluetooth.

## Menu

- **Connected: `<name>`** / **Off / standby** — current state.
- **Turn On / Turn Off** — switches with the connection state.
- **Connect Audio** — reconnects the classic audio profile.
- **Battery: `n%`** — click to refresh over BLE.
- **Set as Default Output** — best-effort switch via `SwitchAudioSource`.
- **Quit**.

State is refreshed every 15 seconds and after every action. All Bluetooth work
runs off the main thread.

## Configuration

Settings are stored in `UserDefaults` (bundle id `com.synchro.boombar`) under
the `BoomBar.` prefix:

- `hostMAC` — this Mac's Bluetooth address (auto-detected).
- `speakerMAC` / `speakerName` / `speakerModel` — the paired speaker's classic
  address, advertised name, and model string.
- `peripheralIdentifier` — the speaker's CoreBluetooth identifier, cached for
  faster battery reads and for BLE control when the speaker isn't advertising.
- `payloadHex` — optional raw wake payload override.
- `setAsDefaultOutput` — the menu checkbox state.

## Protocol notes

- BLE service UUIDs used for discovery: `FE61` / `FE9F`; advertised names
  containing `UE `, `BOOM`, `MEGABOOM`, `HYPERBOOM`, `EPICBOOM`, `EVERBOOM`;
  Logitech manufacturer id `224`.
- Battery: standard GATT `00002A19-0000-1000-8000-00805F9B34FB` (uint8 percent).
- The standby control characteristic only exists while the speaker is off; its
  absence is treated as "already on".
- A stale ACL link can make the RFCOMM open fail with `kIOReturnError`
  (`0xE00002BC`); the app drops the classic connection, reopens it, and retries.

## Disclaimer

This uses reverse-engineered behaviour, not an official Ultimate Ears API.
Behaviour may vary by speaker generation and firmware. See
[docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for packaging and distribution.
