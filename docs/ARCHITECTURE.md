# Architecture — BrightnessController

Three SwiftPM targets, zero external dependencies, Swift 6 strict concurrency.

```
┌─────────────────────────────────────────────────────────┐
│ brightness (executable)   │ BrightnessBar (executable)  │
│   BrightnessCLI — args    │   MenuBarExtra + sliders    │
│   Commands — get/set/up/  │   AppModel — hot-plug,      │
│    down/max/min/list/     │    launch-at-login          │
│    diagnose               │   DisplayViewModel — debounce│
├─────────────────────────────────────────────────────────┤
│ DDCKit (library)                                        │
│   DisplayManager — discovery + CG↔IOKit matching        │
│   Display        — value type: identity + optional link │
│   DDCLink        — actor: DDC/CI protocol over I2C      │
│   Capabilities   — MCCS capabilities-string parser      │
│   EDID           — EDID parser (identity fields)        │
│   VCPCode        — MCCS feature codes + names           │
│   DDCError       — typed error taxonomy                 │
│   IOAVService    — @_silgen_name bindings to IOKit      │
└─────────────────────────────────────────────────────────┘
                          │
              IOKit (public framework,
               unheadered IOAVService exports)
                          │
        DCP driver stack → DP AUX (I2C-over-AUX)
                          │
                USB-C DP Alt Mode cable
                          │
             Monitor scaler (Realtek) → backlight
```

## Layer responsibilities

### IOAVService.swift — the only "unsafe" boundary

Four `@_silgen_name` declarations binding to symbols that IOKit exports
without headers (`IOAVServiceCreateWithService`, `IOAVServiceCopyEDID`,
`IOAVServiceReadI2C`, `IOAVServiceWriteI2C`). Everything above this file is
ordinary safe Swift. No Objective-C, no C shim target: since the symbols are
plain C functions exported by a framework we already link, direct symbol
binding is the smallest possible surface. If Apple ever renames them, this
one file is the only thing to change.

### DDCLink (actor) — protocol + serialization

One actor instance per display. Being an actor gives us, for free, the two
things a DDC bus needs:

1. **Serialization** — DDC/CI is a single-master protocol on a slow I2C bus;
   concurrent transactions would interleave and corrupt replies. Actor
   isolation makes overlapping calls queue instead.
2. **Timing** — the spec requires quiet time between transactions (~40 ms
   between a request and reading its reply; ~20 ms between transactions).
   Delays are `Task.sleep`, so waiting doesn't block threads.

Protocol details implemented (VESA DDC/CI over I2C address 0x37):

- **Get VCP (op 0x01):** write `[0x82, 0x01, code, chk]` at offset 0x51,
  read an 11-byte reply `6E 88 02 RC CODE TYPE MAXH MAXL CURH CURL CHK`.
  Checksums: host packets seeded with `0x6E ^ 0x51`; replies verified with
  seed `0x50`. Result code 0x01 in the reply = "unsupported feature" and is
  surfaced as `DDCError.unsupportedFeature` (and never retried — it is a
  definitive answer, not a transmission error).
- **Set VCP (op 0x03):** write `[0x84, 0x03, code, hi, lo, chk]`. The spec
  provides no acknowledgement, so the CLI always reads the value back and
  reports what the monitor actually did.
- **Capabilities (op 0xF3):** fragmented request/reply loop, 32-byte
  fragments reassembled until an empty fragment terminates the string.
- **Retries:** 3 attempts with back-off for transport-level failures and
  checksum mismatches (cheap scalers occasionally fumble a reply).

### DisplayManager — discovery and matching

Two enumerations joined by EDID identity:

- **IORegistry side:** all `DCPAVServiceProxy` nodes with
  `Location = External` (the `Embedded` one is the built-in panel on
  laptops). Each yields a `DDCLink` and the display's EDID.
- **CoreGraphics side:** `CGGetOnlineDisplayList`, excluding built-ins.

Matching key: EDID vendor/product/serial ↔ `CGDisplayVendorNumber` /
`CGDisplayModelNumber` / `CGDisplaySerialNumber`. Fallback: if exactly one
external display and one AV service exist, pair them. A CG display with no
matching AV service still appears in `list` (honestly marked
"DDC unavailable") rather than being hidden.

Display IDs are 1-based in sorted CGDisplayID order — stable for a given
set of connected displays.

### Error taxonomy (DDCError)

Every failure mode requested in the spec maps to a case:

| Requirement | Case |
|---|---|
| DDC unavailable | `.ddcUnavailable(String)` |
| Unsupported monitor/feature | `.unsupportedFeature(VCPCode)` |
| Communication failure | `.writeFailed(IOReturn)` / `.readFailed(IOReturn)` |
| Corrupt reply | `.invalidResponse([UInt8])` (carries raw bytes) |
| Timeout | `.timeout(VCPCode)` after retries exhausted |
| Invalid brightness value | `.invalidValue(requested:maximum:)` |
| Bad display selector | `.displayNotFound(Int)` |

CLI exit codes: `0` success, `2` DDC/hardware errors, `64` (EX_USAGE) for
malformed command lines, `1` for anything else.

### Concurrency model

- `DDCLink` is an actor; `Display`, `EDID`, `VCPValue`, `Capabilities`,
  `DDCError` are `Sendable` value types.
- The CFTypeRef for the AV service lives inside the actor and never crosses
  an isolation boundary; the actor is constructed from a plain
  `io_service_t` (a `UInt32`).
- The whole package compiles in Swift 6 language mode with strict
  concurrency and no warnings.

## Extension points

- **Contrast / volume CLI verbs:** `DDCLink.read/write` already take any
  `VCPCode`; add a subcommand that passes `.contrast` or `.audioVolume`.
- **Menu bar app (implemented as `BrightnessBar`):** a `MenuBarExtra`
  (window style) with a native `Slider` per display. Slider movements
  update the UI immediately and debounce hardware writes by 80 ms through
  the display's `DDCLink`; values re-sync from the hardware each time the
  menu opens. `NSApplication.didChangeScreenParametersNotification`
  triggers re-discovery on connect/disconnect. Last brightness is
  remembered per display (keyed by EDID identity) and optionally restored
  on reconnect. Launch-at-login uses `SMAppService`, which requires the
  `.app` bundle produced by `Scripts/make-app.sh` (a bare SwiftPM binary
  can't register). No new hardware code was needed — DDCKit is the whole
  hardware layer.

  Control Center integration was investigated and ruled out: the Display
  module lists only Apple-protocol displays and offers no third-party
  extension point; the macOS 26 Controls API admits buttons/toggles, not
  sliders in the Display menu.
