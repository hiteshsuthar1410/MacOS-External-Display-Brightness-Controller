//  Display.swift
//  DDCKit

import CoreGraphics

/// One physical display attached to the machine, with its DDC channel
/// (if the transport exposes one).
public struct Display: Sendable {
    /// Stable-for-this-session identifier used by `--display`.
    /// Numbered from 1 in CoreGraphics display order.
    public let id: Int

    /// CoreGraphics display ID, if this display could be matched to an
    /// online CG display.
    public let cgDisplayID: CGDirectDisplayID?

    /// Parsed EDID identity, if readable.
    public let edid: EDID?

    /// DDC/CI channel. `nil` when the display has no reachable DDC bus
    /// (e.g. built-in panels, some adapters, virtual displays).
    public let link: DDCLink?

    /// Best-effort transport description derived from the IORegistry path.
    public let transport: String

    /// Full IORegistry path of the AV service, for diagnostics.
    public let registryPath: String?

    /// Monitor name: EDID display descriptor if present.
    public var name: String {
        edid?.displayName ?? "Display \(id)"
    }

    public var manufacturer: String {
        edid?.manufacturerName ?? "Unknown"
    }

    public var modelDescription: String {
        guard let edid else { return "Unknown" }
        return "Product 0x\(String(format: "%04X", edid.productCode)) (\(edid.productCode))"
    }

    public var serialDescription: String {
        guard let edid else { return "Unknown" }
        if let s = edid.serialString, !s.isEmpty { return s }
        return edid.serialNumber == 0 ? "Not reported" : String(edid.serialNumber)
    }
}
