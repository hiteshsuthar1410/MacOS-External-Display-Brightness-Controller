//  Capabilities.swift
//  DDCKit
//
//  Parser for the MCCS capabilities string, e.g.
//  "(prot(monitor)type(lcd)model(PM161Q)cmds(01 02 03 07 0C E3 F3)
//    vcp(02 04 05 08 10 12 14(05 08 0B) 16 18 1A 60(11 12) ...)mccs_ver(2.2))"

/// Parsed view of a display's MCCS capabilities string.
public struct Capabilities: Sendable {
    /// The raw string exactly as the display returned it.
    public let raw: String
    /// Model name advertised in the capabilities string, if any.
    public let model: String?
    /// MCCS version advertised, if any.
    public let mccsVersion: String?
    /// VCP feature codes the display claims to support, with any
    /// enumerated allowed values for non-continuous features.
    public let vcpCodes: [(code: VCPCode, allowedValues: [UInt8])]

    public init(raw: String) {
        self.raw = raw
        self.model = Self.section("model", in: raw)
        self.mccsVersion = Self.section("mccs_ver", in: raw) ?? Self.section("mswhql", in: raw).flatMap { _ in nil }
        if let vcpBody = Self.section("vcp", in: raw) {
            self.vcpCodes = Self.parseVCPList(vcpBody)
        } else {
            self.vcpCodes = []
        }
    }

    /// Whether the display advertises a VCP feature in its capabilities.
    public func supports(_ code: VCPCode) -> Bool {
        vcpCodes.contains { $0.code == code }
    }

    // MARK: - Parsing

    /// Extracts the parenthesized body following `name(`, honoring nesting.
    private static func section(_ name: String, in raw: String) -> String? {
        guard let start = raw.range(of: name + "(") else { return nil }
        var depth = 1
        var body = ""
        for ch in raw[start.upperBound...] {
            if ch == "(" { depth += 1 }
            if ch == ")" {
                depth -= 1
                if depth == 0 { return body }
            }
            body.append(ch)
        }
        return nil
    }

    /// Parses "02 04 10 14(05 08 0B) 60(11 12)" into codes + allowed values.
    private static func parseVCPList(_ body: String) -> [(VCPCode, [UInt8])] {
        var results: [(VCPCode, [UInt8])] = []
        var scanner = Substring(body)

        func skipSpaces() {
            scanner = scanner.drop(while: { $0 == " " || $0 == "\n" || $0 == "\r" })
        }
        func readHexByte() -> UInt8? {
            skipSpaces()
            let token = scanner.prefix(while: { $0.isHexDigit })
            guard !token.isEmpty, token.count <= 2, let value = UInt8(token, radix: 16) else { return nil }
            scanner = scanner.dropFirst(token.count)
            return value
        }

        while true {
            guard let code = readHexByte() else { break }
            var allowed: [UInt8] = []
            skipSpaces()
            if scanner.first == "(" {
                scanner = scanner.dropFirst()
                while let v = readHexByte() { allowed.append(v) }
                skipSpaces()
                if scanner.first == ")" { scanner = scanner.dropFirst() }
            }
            results.append((VCPCode(rawValue: code), allowed))
        }
        return results
    }
}
