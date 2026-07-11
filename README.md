# MacOS External Display Brightness Controller

Real **hardware backlight control** for external monitors on Apple Silicon
Macs, over DDC/CI — exactly like pressing the monitor's physical buttons. No
overlays, no gamma tables, no software dimming.

Two front-ends on one pure-Swift hardware library:

- **`brightness`** — a command-line tool
- **`BrightnessBar`** — a SwiftUI menu bar app with a native slider per display

Built and verified against an **Acer PM161Q B1** portable monitor connected
to a Mac mini M4 over a single USB-C cable (DisplayPort Alt Mode). See
[docs/FEASIBILITY.md](docs/FEASIBILITY.md) for the investigation with raw
wire captures, and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design.

## Requirements

- Apple Silicon Mac (M1 or later) — the DDC path used here is the
  DCP/`IOAVService` stack, which is Apple Silicon-specific
- **macOS 26 or later**
- Xcode command-line tools (Swift 6.2+)

No root, no entitlements, no permission prompts.

## Menu bar app (BrightnessBar)

```bash
./Scripts/make-app.sh          # builds dist/BrightnessBar.app
cp -R dist/BrightnessBar.app /Applications/
open /Applications/BrightnessBar.app
```

A ☀️ icon appears in the menu bar with:

- A **native slider per external display** driving the monitor's real
  backlight over DDC/CI (writes are debounced so dragging stays smooth;
  values re-sync from the hardware every time the menu opens, so changes
  made with the monitor's physical buttons show up correctly)
- **Launch at login** toggle (`SMAppService`; requires running the `.app`
  bundle, which is why `make-app.sh` exists)
- **Restore brightness on reconnect** — remembers the last brightness per
  display (keyed by EDID identity) and reapplies it when that display
  reconnects, if enabled
- Automatic re-discovery when displays are plugged/unplugged
- Quit button

> **Why not inside macOS's own brightness menu?** Control Center's Display
> module only lists Apple-protocol displays (built-in panels, Studio
> Display, Pro Display XDR) and has no extension point for third-party
> displays. macOS 26's Controls API allows third-party buttons/toggles in
> Control Center, but not sliders inside the Display module. A menu bar
> item is the closest native-feeling equivalent.

## CLI (`brightness`)

```bash
swift build -c release
sudo cp .build/release/brightness /usr/local/bin/   # optional
```

```
brightness get                 # print current hardware brightness
brightness set 70              # absolute value (0–100)
brightness up 10               # relative, default step 10
brightness down 10
brightness max
brightness min
brightness list                # all displays: identity, transport, DDC status
brightness diagnose            # full DDC/CI report with raw I2C traffic
brightness set 70 --display 2  # target a specific display from `list`
```

Every write is confirmed by reading the value back from the monitor, so a
success message means the hardware actually changed, not merely that the
command was sent.

### Example output

```
$ brightness list
Display 1: PM161Q B1
  Manufacturer:  Acer
  Model:         Product 0x0F04 (3844)
  Serial:        3617008A23X00
  Transport:     DisplayPort (native or USB-C Alt Mode)
  CG display ID: 3
  Brightness:    100 / 100
  Contrast:      50 / 100

$ brightness set 70
PM161Q B1: brightness → 70
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | DDC/hardware error (unavailable, timeout, unsupported, bad value, unknown display) |
| 64 | Usage error (bad command line) |

## How it works

On Apple Silicon, each external display's DDC/CI channel is exposed in the
IORegistry as a `DCPAVServiceProxy` node (`Location = External`). IOKit
exports unheadered functions (`IOAVServiceCreateWithService`,
`IOAVServiceReadI2C`, `IOAVServiceWriteI2C`, `IOAVServiceCopyEDID`) that
perform raw I2C transactions on that bus. `DDCKit` binds those four symbols
from pure Swift and implements the VESA DDC/CI protocol (MCCS Get/Set VCP,
capabilities request) on top, with an actor serializing bus access. Both
the CLI and the menu bar app are thin layers over `DDCKit`.

## Troubleshooting

Run `brightness diagnose` first — it prints the raw DDC transactions and a
per-display recommendation.

- **Monitor doesn't respond:** wake the display and make sure it isn't in
  power-save. Displays park their DDC interface when asleep.
- **Connected through a dock/adapter:** some adapters drop the DDC lines.
  `diagnose` will show the display with no matched DDC service. Prefer a
  direct cable.
- **Values fight with other software:** quit other DDC tools
  (MonitorControl, Lunar, BetterDisplay) while testing — two masters on one
  DDC bus confuse cheap scalers.
- **Capabilities string looks empty:** normal for the PM161Q. Its firmware
  advertises almost nothing (`vcp(02)`) but empirically supports
  brightness, contrast, volume and power mode. `diagnose` calls this out.

## Known limitations

- Intel Macs are unsupported (they need the legacy IOFramebuffer path —
  use `ddcctl` there instead).
- Apple displays (built-in, Studio Display, Pro Display XDR) don't speak
  DDC/CI and are intentionally excluded; macOS already provides brightness
  keys for them.
- The `IOAVService` functions are exported by IOKit but unheadered — a
  private API surface, stable since macOS 11 and shared with
  MonitorControl/Lunar/BetterDisplay/m1ddc, but not contractual.
- Input-source switching (VCP 0x60) is not exposed: the PM161Q's firmware
  returns implausible values for that feature (details in the feasibility
  report).

## Package layout

```
Package.swift
Sources/
  DDCKit/         # library: discovery, DDC/CI protocol, EDID, errors
  brightness/     # CLI executable
  BrightnessBar/  # SwiftUI menu bar app
Scripts/
  make-app.sh     # wraps BrightnessBar in a signed .app bundle
docs/
  FEASIBILITY.md
  ARCHITECTURE.md
```
