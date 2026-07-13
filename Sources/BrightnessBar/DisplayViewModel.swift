//  DisplayViewModel.swift
//  BrightnessBar

import DDCKit
import Foundation
import Observation

/// A color-temperature preset button (MCCS VCP 0x14 value + label).
/// The values were write-verified on the PM161Q; monitors that reject a
/// value simply keep their current preset, and the readback corrects the UI.
struct ColorPreset: Identifiable, Sendable {
    let value: Int
    let label: String
    let detail: String
    var id: Int { value }

    static let all: [ColorPreset] = [
        ColorPreset(value: 1, label: "sRGB", detail: "sRGB color space"),
        ColorPreset(value: 4, label: "Warm", detail: "5000 K"),
        ColorPreset(value: 5, label: "Normal", detail: "6500 K"),
        ColorPreset(value: 8, label: "Cool", detail: "9300 K"),
    ]
}

/// Per-display state binding the menu controls to the monitor's real
/// hardware (backlight, contrast, color preset, speaker volume).
@MainActor
@Observable
final class DisplayViewModel: Identifiable {
    let display: Display

    /// Brightness slider value. Updated immediately for a responsive UI;
    /// hardware writes are debounced behind it.
    var brightness: Double
    let maximum: Double

    /// Contrast slider value, or nil when the display doesn't answer
    /// VCP 0x12. The slider has a detent at the midpoint (the panel's
    /// neutral setting): values within ±2 of mid snap to it.
    var contrast: Double?
    let contrastMaximum: Double
    var contrastMidpoint: Double { (contrastMaximum / 2).rounded() }

    /// Active color preset (VCP 0x14 value), or nil when unsupported.
    var colorPreset: Int?

    /// Volume slider value, or nil when the display doesn't answer
    /// VCP 0x62 (no speakers / no volume control).
    var volume: Double?
    let volumeMaximum: Double

    private let link: DDCLink
    private var brightnessWriteTask: Task<Void, Never>?
    private var contrastWriteTask: Task<Void, Never>?
    private var volumeWriteTask: Task<Void, Never>?

    nonisolated var id: Int { display.id }
    var name: String { display.name }

    /// Stable identity across reconnects, used to remember values.
    private var identityKey: String {
        guard let edid = display.edid else { return "display-\(display.id)" }
        return "\(edid.manufacturerID)-\(edid.productCode)-\(edid.serialString ?? String(edid.serialNumber))"
    }

    var persistenceKey: String { "lastBrightness.\(identityKey)" }
    var contrastPersistenceKey: String { "lastContrast.\(identityKey)" }
    var presetPersistenceKey: String { "lastPreset.\(identityKey)" }
    var volumePersistenceKey: String { "lastVolume.\(identityKey)" }

    var savedBrightness: Int? {
        UserDefaults.standard.object(forKey: persistenceKey) as? Int
    }
    var savedContrast: Int? {
        UserDefaults.standard.object(forKey: contrastPersistenceKey) as? Int
    }
    var savedPreset: Int? {
        UserDefaults.standard.object(forKey: presetPersistenceKey) as? Int
    }
    var savedVolume: Int? {
        UserDefaults.standard.object(forKey: volumePersistenceKey) as? Int
    }

    init(
        display: Display,
        link: DDCLink,
        value: VCPValue,
        contrastValue: VCPValue?,
        presetValue: VCPValue?,
        volumeValue: VCPValue?
    ) {
        self.display = display
        self.link = link
        self.brightness = Double(value.current)
        self.maximum = Double(max(value.maximum, 1))
        self.contrast = contrastValue.map { Double($0.current) }
        self.contrastMaximum = Double(max(contrastValue?.maximum ?? 100, 1))
        self.colorPreset = presetValue.map(\.current)
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

    // MARK: - Contrast

    /// Contrast slider callback with a midpoint detent: the panel's
    /// neutral contrast is the middle of its range, so the slider snaps
    /// there when released nearby.
    func contrastSliderMoved(to value: Double) {
        var snapped = value
        if abs(value - contrastMidpoint) <= 2 {
            snapped = contrastMidpoint
        }
        contrast = snapped
        contrastWriteTask?.cancel()
        contrastWriteTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await self?.apply(contrast: snapped)
        }
    }

    /// Writes contrast to the hardware and remembers it.
    func apply(contrast value: Double) async {
        let target = Int(value.rounded())
        do {
            try await link.write(.contrast, value: target)
            contrast = Double(target)
            UserDefaults.standard.set(target, forKey: contrastPersistenceKey)
        } catch {
            if let actual = try? await link.read(.contrast) {
                contrast = Double(actual.current)
            }
        }
    }

    // MARK: - Color preset

    /// Selects a color-temperature preset and confirms it by readback
    /// (the firmware silently ignores values it doesn't implement).
    func select(preset value: Int) async {
        do {
            try await link.write(.colorPreset, value: value)
            let actual = try await link.read(.colorPreset)
            colorPreset = actual.current
            UserDefaults.standard.set(actual.current, forKey: presetPersistenceKey)
        } catch {
            if let actual = try? await link.read(.colorPreset) {
                colorPreset = actual.current
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
        if contrast != nil, let value = try? await link.read(.contrast) {
            contrast = Double(value.current)
        }
        if colorPreset != nil, let value = try? await link.read(.colorPreset) {
            colorPreset = value.current
        }
        if volume != nil, let value = try? await link.read(.audioVolume) {
            volume = Double(value.current)
        }
    }
}
