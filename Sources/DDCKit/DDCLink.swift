//  DDCLink.swift
//  DDCKit
//
//  Actor that owns the I2C channel to one display and speaks the DDC/CI
//  protocol over it. All transactions are serialized through the actor,
//  which also enforces the inter-transaction quiet time the DDC spec
//  requires (displays are slow I2C devices).

import Foundation
import IOKit

/// A DDC/CI communication channel to a single external display.
///
/// DDC/CI frames ride on I2C address 0x37. Every host→display packet is
/// prefixed with source address 0x51, and checksummed with XOR starting
/// from the destination address (0x6E for writes, 0x50 for replies).
public actor DDCLink {
    private let service: IOAVServiceRef

    /// I2C slave address of the DDC/CI interface (7-bit 0x37).
    private static let chipAddress: UInt32 = 0x37
    /// Host source address byte used as the I2C register offset.
    private static let hostAddress: UInt32 = 0x51

    private static let writeReadDelay: UInt64 = 40_000_000  // 40 ms
    private static let betweenTransactions: UInt64 = 20_000_000  // 20 ms
    private static let attempts = 3

    /// Opens the DDC channel for a `DCPAVServiceProxy` registry entry.
    /// - Throws: `DDCError.ddcUnavailable` if the AV service can't be created.
    init(ioService: io_service_t) throws {
        guard let svc = IOAVServiceCreateWithService(kCFAllocatorDefault, ioService)?.takeRetainedValue() else {
            throw DDCError.ddcUnavailable("IOAVServiceCreateWithService returned nil for the display's AV service")
        }
        self.service = svc
    }

    // MARK: - Public protocol operations

    /// Reads a continuous VCP feature ("Get VCP Feature" op 0x01).
    public func read(_ code: VCPCode) async throws -> VCPValue {
        let reply = try await transactWithRetry(code: code) {
            try await self.getVCPOnce(code)
        }
        return reply
    }

    /// Writes a continuous VCP feature ("Set VCP Feature" op 0x03).
    ///
    /// The DDC set operation has no acknowledgement; callers that need
    /// confirmation should `read` the value back afterwards.
    public func write(_ code: VCPCode, value: Int) async throws {
        var packet: [UInt8] = [0x84, 0x03, code.rawValue, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        packet[5] = Self.checksum(seed: 0x6E ^ 0x51, bytes: packet[0...4])

        var lastError: DDCError = .timeout(code)
        for _ in 0..<Self.attempts {
            do {
                try await i2cWrite(packet)
                return
            } catch let error as DDCError {
                lastError = error
                try? await Task.sleep(nanoseconds: Self.betweenTransactions)
            }
        }
        throw lastError
    }

    /// Fetches and parses the display's MCCS capabilities string
    /// ("Capabilities Request" op 0xF3), reassembling it from 32-byte
    /// fragments.
    public func capabilities() async throws -> Capabilities {
        var result: [UInt8] = []
        var offset: UInt16 = 0

        while result.count < 4096 {
            var request: [UInt8] = [0x83, 0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF), 0]
            request[4] = Self.checksum(seed: 0x6E ^ 0x51, bytes: request[0...3])

            try await i2cWrite(request)
            try await Task.sleep(nanoseconds: Self.writeReadDelay)
            let reply = try await i2cRead(count: 38)

            // Reply: 6E len|0x80 0xE3 offHi offLo <data…> chk
            guard reply.count >= 6, reply[0] == 0x6E, reply[2] == 0xE3 else {
                throw DDCError.invalidResponse(reply)
            }
            let payloadLength = Int(reply[1] & 0x7F)  // includes op + 2 offset bytes
            let dataLength = payloadLength - 3
            guard dataLength >= 0, 2 + payloadLength < reply.count else {
                throw DDCError.invalidResponse(reply)
            }
            if dataLength == 0 { break }  // empty fragment = end of string

            result.append(contentsOf: reply[5..<(5 + dataLength)])
            offset += UInt16(dataLength)
            try await Task.sleep(nanoseconds: Self.betweenTransactions)
        }

        return Capabilities(raw: String(decoding: result, as: UTF8.self))
    }

    /// Copies and parses the display's EDID.
    public func readEDID() throws -> EDID {
        var unmanaged: Unmanaged<CFData>? = nil
        let result = IOAVServiceCopyEDID(service, &unmanaged)
        guard result == KERN_SUCCESS, let data = unmanaged?.takeRetainedValue() as Data? else {
            throw DDCError.readFailed(result)
        }
        guard let edid = EDID(data: data) else {
            throw DDCError.invalidResponse([UInt8](data.prefix(16)))
        }
        return edid
    }

    /// Performs one raw Get VCP transaction and returns the reply bytes
    /// without interpretation. Used by diagnostics.
    public func rawGetVCP(_ code: VCPCode) async throws -> [UInt8] {
        try await sendGetVCPRequest(code)
        try await Task.sleep(nanoseconds: Self.writeReadDelay)
        return try await i2cRead(count: 12)
    }

    // MARK: - Single Get VCP transaction

    private func getVCPOnce(_ code: VCPCode) async throws -> VCPValue {
        try await sendGetVCPRequest(code)
        try await Task.sleep(nanoseconds: Self.writeReadDelay)
        let reply = try await i2cRead(count: 12)

        // Reply layout: 6E 88 02 RC CODE TYPE MAXH MAXL CURH CURL CHK
        guard reply.count >= 11, reply[0] == 0x6E, reply[1] == 0x88, reply[2] == 0x02 else {
            throw DDCError.invalidResponse(reply)
        }
        guard Self.checksum(seed: 0x50, bytes: reply[0...9]) == reply[10] else {
            throw DDCError.invalidResponse(reply)
        }
        // Result code 0x01 = unsupported VCP code.
        if reply[3] == 0x01 {
            throw DDCError.unsupportedFeature(code)
        }
        guard reply[3] == 0x00, reply[4] == code.rawValue else {
            throw DDCError.invalidResponse(reply)
        }
        return VCPValue(
            current: Int(reply[8]) << 8 | Int(reply[9]),
            maximum: Int(reply[6]) << 8 | Int(reply[7])
        )
    }

    private func sendGetVCPRequest(_ code: VCPCode) async throws {
        var request: [UInt8] = [0x82, 0x01, code.rawValue, 0]
        request[3] = Self.checksum(seed: 0x6E ^ 0x51, bytes: request[0...2])
        try await i2cWrite(request)
    }

    // MARK: - Retry wrapper

    private func transactWithRetry<T: Sendable>(
        code: VCPCode,
        _ body: () async throws -> T
    ) async throws -> T {
        var lastError: Error = DDCError.timeout(code)
        for attempt in 0..<Self.attempts {
            do {
                return try await body()
            } catch let error as DDCError {
                // Unsupported is a definitive answer from the display; don't retry.
                if case .unsupportedFeature = error { throw error }
                lastError = error
                if attempt < Self.attempts - 1 {
                    try? await Task.sleep(nanoseconds: Self.betweenTransactions * 2)
                }
            }
        }
        throw lastError
    }

    // MARK: - Raw I2C

    private func i2cWrite(_ bytes: [UInt8]) async throws {
        try await Task.sleep(nanoseconds: Self.betweenTransactions)
        let result = bytes.withUnsafeBytes {
            IOAVServiceWriteI2C(service, Self.chipAddress, Self.hostAddress, $0.baseAddress!, UInt32(bytes.count))
        }
        guard result == KERN_SUCCESS else {
            throw DDCError.writeFailed(result)
        }
    }

    private func i2cRead(count: Int) async throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        let result = buffer.withUnsafeMutableBytes {
            IOAVServiceReadI2C(service, Self.chipAddress, Self.hostAddress, $0.baseAddress!, UInt32(count))
        }
        guard result == KERN_SUCCESS else {
            throw DDCError.readFailed(result)
        }
        return buffer
    }

    private static func checksum(seed: UInt8, bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(seed) { $0 ^ $1 }
    }
}
