//  DisplayViewModel.swift
//  BrightnessBar

import DDCKit
import Foundation
import Observation

/// Per-display state binding a slider to the monitor's real backlight.
@MainActor
@Observable
final class DisplayViewModel: Identifiable {
    let display: Display
    let maximum: Double
    /// Slider value. Updated immediately for a responsive UI; hardware
    /// writes are debounced behind it.
    var brightness: Double

    private let link: DDCLink
    private var writeTask: Task<Void, Never>?

    nonisolated var id: Int { display.id }
    var name: String { display.name }

    /// Stable identity across reconnects, used to remember brightness.
    var persistenceKey: String {
        guard let edid = display.edid else { return "display-\(display.id)" }
        return "lastBrightness.\(edid.manufacturerID)-\(edid.productCode)-\(edid.serialString ?? String(edid.serialNumber))"
    }

    var savedBrightness: Int? {
        UserDefaults.standard.object(forKey: persistenceKey) as? Int
    }

    init(display: Display, link: DDCLink, value: VCPValue) {
        self.display = display
        self.link = link
        self.brightness = Double(value.current)
        self.maximum = Double(max(value.maximum, 1))
    }

    /// Slider callback: update the UI instantly, coalesce rapid movements,
    /// and write the final value to the monitor. The DDC bus is slow
    /// (~100 ms per transaction), so writing every tick would lag the drag.
    func sliderMoved(to value: Double) {
        brightness = value
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await self?.apply(brightness: value)
        }
    }

    /// Writes brightness to the hardware and remembers it.
    func apply(brightness value: Double) async {
        let target = Int(value.rounded())
        do {
            try await link.write(.brightness, value: target)
            brightness = Double(target)
            UserDefaults.standard.set(target, forKey: persistenceKey)
        } catch {
            // Re-sync the slider with reality if the write failed.
            if let actual = try? await link.read(.brightness) {
                brightness = Double(actual.current)
            }
        }
    }

    /// Re-reads the hardware value (e.g. when the menu opens, in case the
    /// monitor's physical buttons were used meanwhile).
    func sync() async {
        if let value = try? await link.read(.brightness) {
            brightness = Double(value.current)
        }
    }
}
