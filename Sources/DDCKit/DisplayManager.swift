//  DisplayManager.swift
//  DDCKit
//
//  Discovers external displays and pairs each one's CoreGraphics identity
//  with its DDC/CI channel from the IORegistry.

import CoreGraphics
import Foundation
import IOKit

/// Discovers displays and their DDC channels.
public enum DisplayManager {

    /// Enumerates all online displays and attaches a `DDCLink` to each
    /// external display whose transport exposes a DDC bus.
    ///
    /// Matching strategy: each `DCPAVServiceProxy` (Location = External)
    /// carries the EDID of the display behind it; the EDID's vendor,
    /// product and serial numbers are matched against
    /// `CGDisplayVendorNumber` / `ModelNumber` / `SerialNumber`. If there
    /// is exactly one unmatched external CG display and one unmatched AV
    /// service, they are paired as a fallback.
    public static func discover() async throws -> [Display] {
        let services = try discoverAVServices()

        // Read EDIDs for every service up front.
        var candidates: [(link: DDCLink, edid: EDID?, path: String)] = []
        for service in services {
            let edid = try? await service.link.readEDID()
            candidates.append((service.link, edid, service.path))
        }

        // Online CG displays, external only.
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(16, &displayIDs, &displayCount)
        let external = displayIDs.prefix(Int(displayCount)).filter { CGDisplayIsBuiltin($0) == 0 }

        var displays: [Display] = []
        var usedCandidates = Set<Int>()

        for (index, cgID) in external.sorted().enumerated() {
            let vendor = CGDisplayVendorNumber(cgID)
            let model = CGDisplayModelNumber(cgID)
            let serial = CGDisplaySerialNumber(cgID)

            var matched: Int? = nil
            for (i, candidate) in candidates.enumerated() where !usedCandidates.contains(i) {
                guard let edid = candidate.edid else { continue }
                if edid.vendorNumber == vendor && edid.productCode == model
                    && (serial == 0 || edid.serialNumber == serial) {
                    matched = i
                    break
                }
            }
            // Fallback: single external display, single DDC service.
            if matched == nil, external.count == 1, candidates.count == 1, usedCandidates.isEmpty {
                matched = 0
            }

            if let i = matched {
                usedCandidates.insert(i)
                let c = candidates[i]
                displays.append(Display(
                    id: index + 1,
                    cgDisplayID: cgID,
                    edid: c.edid,
                    link: c.link,
                    transport: Self.transport(fromRegistryPath: c.path),
                    registryPath: c.path
                ))
            } else {
                displays.append(Display(
                    id: index + 1,
                    cgDisplayID: cgID,
                    edid: nil,
                    link: nil,
                    transport: "Unknown (no DDC service matched)",
                    registryPath: nil
                ))
            }
        }

        return displays
    }

    /// Returns the display with the given identifier, or the only display
    /// if no identifier was requested.
    public static func select(from displays: [Display], id requested: Int?) throws -> Display {
        if let requested {
            guard let display = displays.first(where: { $0.id == requested }) else {
                throw DDCError.displayNotFound(requested)
            }
            return display
        }
        guard let first = displays.first else {
            throw DDCError.ddcUnavailable("No external displays are connected.")
        }
        return first
    }

    // MARK: - IORegistry enumeration

    private static func discoverAVServices() throws -> [(link: DDCLink, path: String)] {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("DCPAVServiceProxy")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw DDCError.ddcUnavailable("Could not enumerate DCPAVServiceProxy services in the IORegistry.")
        }
        defer { IOObjectRelease(iterator) }

        var results: [(DDCLink, String)] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            let location = IORegistryEntryCreateCFProperty(
                service, "Location" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String

            // "Embedded" proxies are the built-in panel path; external
            // displays are the only ones with a DDC bus we can drive.
            guard location == "External" else { continue }

            var pathBuffer = [UInt8](repeating: 0, count: 1024)
            _ = pathBuffer.withUnsafeMutableBytes { buffer in
                IORegistryEntryGetPath(service, kIOServicePlane, buffer.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            let path = String(decoding: pathBuffer.prefix(while: { $0 != 0 }), as: UTF8.self)

            if let link = try? DDCLink(ioService: service) {
                results.append((link, path))
            }
        }
        return results
    }

    /// Guesses the video transport from the AV service's registry path.
    private static func transport(fromRegistryPath path: String) -> String {
        let lower = path.lowercased()
        if lower.contains("dptx") || lower.contains("dispext") {
            return "DisplayPort (native or USB-C Alt Mode)"
        }
        if lower.contains("hdmi") {
            return "HDMI"
        }
        return "External (unrecognized transport node)"
    }
}
