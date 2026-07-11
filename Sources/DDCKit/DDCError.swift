//  DDCError.swift
//  DDCKit

import Foundation

/// Errors thrown by DDCKit operations.
public enum DDCError: Error, Sendable {
    /// No DDC-capable external display service exists in the IORegistry,
    /// or the AV service could not be opened.
    case ddcUnavailable(String)

    /// No display matched the requested identifier.
    case displayNotFound(Int)

    /// The requested value is outside the range the monitor reports.
    case invalidValue(requested: Int, maximum: Int)

    /// The I2C write to the display failed at the transport level.
    case writeFailed(IOReturn)

    /// The I2C read from the display failed at the transport level.
    case readFailed(IOReturn)

    /// The display replied, but the packet was malformed or failed its
    /// checksum. Contains the raw reply bytes for diagnostics.
    case invalidResponse([UInt8])

    /// The display replied with "unsupported VCP code" for this feature.
    case unsupportedFeature(VCPCode)

    /// All retry attempts were exhausted without a valid reply.
    case timeout(VCPCode)
}

extension DDCError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .ddcUnavailable(let reason):
            return "DDC/CI is not available: \(reason)"
        case .displayNotFound(let id):
            return "No display with identifier \(id) is connected."
        case .invalidValue(let requested, let maximum):
            return "Value \(requested) is out of range (0–\(maximum))."
        case .writeFailed(let code):
            return "I2C write to the display failed (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16))). The display may be asleep or disconnected."
        case .readFailed(let code):
            return "I2C read from the display failed (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16))). The display may be asleep or disconnected."
        case .invalidResponse(let bytes):
            return "The display sent a malformed DDC reply: [\(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))]"
        case .unsupportedFeature(let code):
            return "The display reports that it does not support VCP feature 0x\(String(format: "%02X", code.rawValue)) (\(code.name))."
        case .timeout(let code):
            return "Timed out waiting for a valid reply to VCP 0x\(String(format: "%02X", code.rawValue)) (\(code.name)) after multiple attempts."
        }
    }
}
