//  DisplayViewModel.swift
//  BrightnessBar

import DDCKit
import Foundation
import Observation

/// Per-display state binding sliders to the monitor's real hardware
/// controls (backlight brightness, and speaker volume where supported).
@MainActor
@Observable
final class DisplayViewModel: Identifiable {
    let display: Display

    /// Brightness slider value. Updated immediately for a responsive UI;
    /// hardware writes are debounced behind it.
    var brightness: Double
    let maximum: Double

    /// Volume slider value, or nil when the display doesn't answer
    /// VCP 0x62 (no speakers / no volume control).
    var volume: Double?
    let volumeMaximum: Double

    private let link: DDCLink
    private var brightnessWriteTask: Task<Void, Never>?
    private var volumeWriteTask: Task<Void, Never>?

    nonisolated var id: Int { display.id }
    var name: String { display.name }

    /// Stable identity across reconnects, used to remember values.
    private var identityKey: String {
        guard let edid = display.edid else { return "display-\(display.id)" }
        return "\(edid.manufacturerID)-\(edid.productCode)-\(edid.serialString ?? String(edid.serialNumber))"
    }

    var persistenceKey: String { "lastBrightness.\(identityKey)" }
    var volumePersistenceKey: String { "lastVolume.\(identityKey)" }

    var savedBrightness: Int? {
        UserDefaults.standard.object(forKey: persistenceKey) as? Int
    }

    var savedVolume: Int? {
        UserDefaults.standard.object(forKey: volumePersistenceKey) as? Int
    }

    init(display: Display, link: DDCLink, value: VCPValue, volumeValue: VCPValue?) {
        self.display = display
        self.link = link
        self.brightness = Double(value.current)
        self.maximum = Double(max(value.maximum, 1))
        self.volume = volumeValue.map { Double($0.current) }
        self.volumeMaximum = Double(max(volumeValue?.maximum ?? 100, 1))
    }

    // MARK: - Brightness

    /// Slider callback: update the UI instantly, coalesce rapid movements,
    /// and write the final value to the monitor. The DDC bus is slow
    /// (~100 ms per transaction), so writing every tick would lag the drag.
    func sliderMoved(to value: Double) {
        brightness = value
        brightnessWriteTask?.cancel()
        brightnessWriteTask = Task { [weak self] in
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

    // MARK: - Volume

    func volumeSliderMoved(to value: Double) {
        volume = value
        volumeWriteTask?.cancel()
        volumeWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await self?.apply(volume: value)
        }
    }

    /// Writes speaker volume to the hardware and remembers it.
    func apply(volume value: Double) async {
        let target = Int(value.rounded())
        do {
            try await link.write(.audioVolume, value: target)
            volume = Double(target)
            UserDefaults.standard.set(target, forKey: volumePersistenceKey)
        } catch {
            if let actual = try? await link.read(.audioVolume) {
                volume = Double(actual.current)
            }
        }
    }

    // MARK: - Sync

    /// Re-reads the hardware values (e.g. when the menu opens, in case the
    /// monitor's physical buttons were used meanwhile).
    func sync() async {
        if let value = try? await link.read(.brightness) {
            brightness = Double(value.current)
        }
        if volume != nil, let value = try? await link.read(.audioVolume) {
            volume = Double(value.current)
        }
    }
}
