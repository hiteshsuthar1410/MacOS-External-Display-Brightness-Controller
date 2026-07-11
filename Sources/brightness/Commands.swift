//  Commands.swift
//  brightness
//
//  Implementations of the CLI subcommands.

import DDCKit
import Foundation

enum Commands {

    // MARK: - get / set / up / down / max / min

    static func get(displayID: Int?) async throws {
        let (display, link) = try await controllableDisplay(id: displayID)
        let value = try await link.read(.brightness)
        print("\(value.current)")
        if value.maximum != 100 {
            print("(maximum: \(value.maximum))")
        }
        _ = display
    }

    static func set(_ requested: Int, displayID: Int?) async throws {
        let (display, link) = try await controllableDisplay(id: displayID)
        let current = try await link.read(.brightness)
        guard requested >= 0 && requested <= current.maximum else {
            throw DDCError.invalidValue(requested: requested, maximum: current.maximum)
        }
        try await apply(requested, to: link, display: display)
    }

    static func adjust(by delta: Int, displayID: Int?) async throws {
        let (display, link) = try await controllableDisplay(id: displayID)
        let current = try await link.read(.brightness)
        let target = min(max(current.current + delta, 0), current.maximum)
        guard target != current.current else {
            print("\(display.name): brightness already at \(current.current)")
            return
        }
        try await apply(target, to: link, display: display)
    }

    static func setToLimit(maximum: Bool, displayID: Int?) async throws {
        let (display, link) = try await controllableDisplay(id: displayID)
        let current = try await link.read(.brightness)
        try await apply(maximum ? current.maximum : 0, to: link, display: display)
    }

    /// Writes the value, then reads it back so success reflects what the
    /// monitor actually did rather than just a successful I2C write.
    private static func apply(_ target: Int, to link: DDCLink, display: Display) async throws {
        try await link.write(.brightness, value: target)
        let confirmed = try await link.read(.brightness)
        if confirmed.current == target {
            print("\(display.name): brightness → \(target)")
        } else {
            print("\(display.name): wrote \(target), but the monitor reports \(confirmed.current)")
        }
    }

    // MARK: - list

    static func list() async throws {
        let displays = try await DisplayManager.discover()
        guard !displays.isEmpty else {
            print("No external displays connected.")
            return
        }

        for display in displays {
            print("Display \(display.id): \(display.name)")
            print("  Manufacturer:  \(display.manufacturer)")
            print("  Model:         \(display.modelDescription)")
            print("  Serial:        \(display.serialDescription)")
            print("  Transport:     \(display.transport)")
            if let cgID = display.cgDisplayID {
                print("  CG display ID: \(cgID)")
            }
            guard let link = display.link else {
                print("  DDC/CI:        unavailable (no DDC service for this display)")
                continue
            }
            do {
                let brightness = try await link.read(.brightness)
                print("  Brightness:    \(brightness.current) / \(brightness.maximum)")
            } catch {
                print("  Brightness:    unreadable (\(shortDescription(error)))")
            }
            do {
                let contrast = try await link.read(.contrast)
                print("  Contrast:      \(contrast.current) / \(contrast.maximum)")
            } catch {
                print("  Contrast:      unreadable (\(shortDescription(error)))")
            }
            if let capabilities = try? await link.capabilities() {
                let codes = capabilities.vcpCodesSummary
                if !codes.isEmpty {
                    print("  Advertised VCP: \(codes)  (from capabilities string; firmware may under-report)")
                }
            }
        }
    }

    // MARK: - diagnose

    static func diagnose() async throws {
        print("brightness diagnose — DDC/CI hardware report")
        print(String(repeating: "=", count: 60))

        let displays: [Display]
        do {
            displays = try await DisplayManager.discover()
        } catch {
            print("Display discovery failed: \(error.localizedDescription)")
            print("\nRecommendation: no external DDC services were found in the")
            print("IORegistry. Check the display connection and try again.")
            return
        }

        if displays.isEmpty {
            print("No external displays detected by CoreGraphics.")
            return
        }

        for display in displays {
            print("\nDisplay \(display.id): \(display.name)")
            print(String(repeating: "-", count: 60))
            print("Manufacturer:   \(display.manufacturer)")
            print("Model:          \(display.modelDescription)")
            print("Serial:         \(display.serialDescription)")
            print("Transport:      \(display.transport)")
            if let path = display.registryPath {
                print("Registry path:  \(path)")
            }
            if let edid = display.edid {
                print("EDID:           \(edid.raw.count) bytes, manufactured \(edid.manufactureYear)")
                print("EDID header:    \(hex(Array(edid.raw.prefix(16))))")
            }

            guard let link = display.link else {
                print("DDC/CI:         UNAVAILABLE — no DCPAVServiceProxy matched this display.")
                print("Recommendation: if this display is connected through a dock or")
                print("adapter, try a direct cable; some adapters drop the DDC lines.")
                continue
            }
            print("DDC/CI:         service opened successfully")

            // Raw brightness transaction.
            print("\nRaw Get VCP 0x10 (brightness) transaction:")
            do {
                let reply = try await link.rawGetVCP(.brightness)
                print("  reply: \(hex(reply))")
            } catch {
                print("  failed: \(error.localizedDescription)")
            }

            var ddcWorks = false
            for code in [VCPCode.brightness, .contrast] {
                do {
                    let value = try await link.read(code)
                    print("VCP 0x\(String(format: "%02X", code.rawValue)) (\(code.name)): current \(value.current), max \(value.maximum)")
                    ddcWorks = true
                } catch {
                    print("VCP 0x\(String(format: "%02X", code.rawValue)) (\(code.name)): \(error.localizedDescription)")
                }
            }

            print("\nCapabilities string (VCP op 0xF3):")
            do {
                let capabilities = try await link.capabilities()
                print("  raw: \(capabilities.raw)")
                if let model = capabilities.model {
                    print("  model: \(model)")
                }
                if !capabilities.vcpCodes.isEmpty {
                    print("  supported VCP features:")
                    for entry in capabilities.vcpCodes {
                        var line = "    0x\(String(format: "%02X", entry.code.rawValue))  \(entry.code.name)"
                        if !entry.allowedValues.isEmpty {
                            line += "  values: [\(entry.allowedValues.map { String(format: "%02X", $0) }.joined(separator: " "))]"
                        }
                        print(line)
                    }
                }
                if ddcWorks && !capabilities.supports(.brightness) {
                    print("  NOTE: the capabilities string does not advertise 0x10, but the")
                    print("  empirical read above succeeded — the firmware under-reports its")
                    print("  features. Trust the empirical reads.")
                }
            } catch {
                print("  failed: \(error.localizedDescription)")
                print("  (Many monitors work fine for get/set even when the")
                print("   capabilities request is unsupported.)")
            }

            print("\nRecommendation:", ddcWorks
                ? "DDC/CI is fully functional. Use `brightness set <0-100>`."
                : "DDC reads failed. Try waking the display, reconnecting the cable, or checking that no other DDC tool is polling the display.")
        }
    }

    // MARK: - Helpers

    /// Discovers displays, selects the target, and requires a DDC link.
    private static func controllableDisplay(id: Int?) async throws -> (Display, DDCLink) {
        let displays = try await DisplayManager.discover()
        let display = try DisplayManager.select(from: displays, id: id)
        guard let link = display.link else {
            throw DDCError.ddcUnavailable(
                "display \(display.id) (\(display.name)) has no DDC channel. Run `brightness diagnose` for details.")
        }
        return (display, link)
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func shortDescription(_ error: Error) -> String {
        (error as? DDCError)?.localizedDescription ?? error.localizedDescription
    }
}

extension Capabilities {
    /// Compact one-line summary of supported VCP codes for `list`.
    var vcpCodesSummary: String {
        vcpCodes.map { String(format: "%02X", $0.code.rawValue) }.joined(separator: " ")
    }
}
