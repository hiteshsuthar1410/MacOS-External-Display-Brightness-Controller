//  VCPCode.swift
//  DDCKit
//
//  MCCS (Monitor Control Command Set) VCP feature codes.

/// A VCP (Virtual Control Panel) feature code as defined by VESA MCCS.
public struct VCPCode: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    // Commonly used continuous controls.
    public static let brightness = VCPCode(rawValue: 0x10)
    public static let contrast = VCPCode(rawValue: 0x12)
    public static let audioVolume = VCPCode(rawValue: 0x62)
    public static let inputSource = VCPCode(rawValue: 0x60)
    public static let powerMode = VCPCode(rawValue: 0xD6)

    /// Human-readable MCCS feature name, for diagnostics output.
    public var name: String {
        Self.names[rawValue] ?? "Unknown / manufacturer-specific"
    }

    private static let names: [UInt8: String] = [
        0x02: "New control value",
        0x04: "Restore factory defaults",
        0x05: "Restore factory luminance",
        0x08: "Restore factory color defaults",
        0x0B: "Color temperature increment",
        0x0C: "Color temperature request",
        0x10: "Brightness (luminance)",
        0x12: "Contrast",
        0x14: "Select color preset",
        0x16: "Video gain: red",
        0x18: "Video gain: green",
        0x1A: "Video gain: blue",
        0x52: "Active control",
        0x60: "Input source",
        0x62: "Audio volume",
        0x6C: "Video black level: red",
        0x6E: "Video black level: green",
        0x70: "Video black level: blue",
        0x87: "Sharpness",
        0x8D: "Audio mute",
        0xAC: "Horizontal frequency",
        0xAE: "Vertical frequency",
        0xB2: "Flat panel sub-pixel layout",
        0xB6: "Display technology type",
        0xC0: "Display usage time",
        0xC6: "Application enable key",
        0xC8: "Display controller ID",
        0xC9: "Display firmware level",
        0xCA: "OSD",
        0xCC: "OSD language",
        0xD6: "Power mode",
        0xDF: "VCP version",
    ]
}

/// The current and maximum value of a continuous VCP feature,
/// as reported by the monitor.
public struct VCPValue: Sendable {
    public let current: Int
    public let maximum: Int
}
