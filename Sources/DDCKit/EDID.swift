//  EDID.swift
//  DDCKit
//
//  Minimal EDID (Extended Display Identification Data) parser — extracts
//  the identity fields needed to name displays and match them to
//  CoreGraphics display IDs.

import Foundation

/// Parsed identity information from a display's EDID block.
public struct EDID: Sendable {
    /// Three-letter PNP manufacturer ID, e.g. "ACR" for Acer.
    public let manufacturerID: String
    /// EDID manufacturer field as a number, matches `CGDisplayVendorNumber`.
    public let vendorNumber: UInt32
    /// Product code, matches `CGDisplayModelNumber`.
    public let productCode: UInt32
    /// 32-bit serial number, matches `CGDisplaySerialNumber` (may be 0).
    public let serialNumber: UInt32
    /// Monitor name from the 0xFC display descriptor, if present.
    public let displayName: String?
    /// Serial string from the 0xFF display descriptor, if present.
    public let serialString: String?
    /// Manufacture year encoded in the EDID.
    public let manufactureYear: Int
    /// The raw EDID bytes.
    public let raw: [UInt8]

    /// Well-known PNP IDs, for friendlier output.
    private static let pnpVendors: [String: String] = [
        "ACR": "Acer", "AOC": "AOC", "APP": "Apple", "AUS": "ASUS",
        "BNQ": "BenQ", "DEL": "Dell", "GSM": "LG", "HPN": "HP",
        "HWP": "HP", "LEN": "Lenovo", "MSI": "MSI", "PHL": "Philips",
        "SAM": "Samsung", "SNY": "Sony", "VSC": "ViewSonic",
    ]

    /// Friendly manufacturer name derived from the PNP ID.
    public var manufacturerName: String {
        Self.pnpVendors[manufacturerID] ?? manufacturerID
    }

    /// Parses the first 128-byte EDID block (plus descriptors).
    /// Returns nil if the data is too short or the header is invalid.
    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 128 else { return nil }
        // 8-byte fixed header 00 FF FF FF FF FF FF 00
        guard bytes[0] == 0x00, bytes[1...6].allSatisfy({ $0 == 0xFF }), bytes[7] == 0x00 else {
            return nil
        }

        raw = bytes

        // Bytes 8–9: manufacturer ID, three 5-bit letters, big-endian.
        let m = (UInt16(bytes[8]) << 8) | UInt16(bytes[9])
        let letters = [(m >> 10) & 0x1F, (m >> 5) & 0x1F, m & 0x1F].map {
            Character(UnicodeScalar(UInt8($0) + 64))
        }
        manufacturerID = String(letters)
        vendorNumber = UInt32(m)

        // Bytes 10–11: product code (little-endian); 12–15: serial (LE).
        productCode = UInt32(bytes[10]) | (UInt32(bytes[11]) << 8)
        serialNumber = UInt32(bytes[12]) | (UInt32(bytes[13]) << 8)
            | (UInt32(bytes[14]) << 16) | (UInt32(bytes[15]) << 24)

        manufactureYear = 1990 + Int(bytes[17])

        // Four 18-byte descriptor blocks at 54, 72, 90, 108.
        // Display descriptors start 00 00 00 <tag> 00.
        func descriptorText(tag: UInt8) -> String? {
            for offset in [54, 72, 90, 108] {
                let d = bytes[offset..<(offset + 18)]
                let db = Array(d)
                guard db[0] == 0, db[1] == 0, db[2] == 0, db[3] == tag else { continue }
                let text = db[5...17]
                    .prefix(while: { $0 != 0x0A })
                    .map { Character(UnicodeScalar($0)) }
                return String(text).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }
        displayName = descriptorText(tag: 0xFC)
        serialString = descriptorText(tag: 0xFF)
    }
}
