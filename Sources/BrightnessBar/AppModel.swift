//  AppModel.swift
//  BrightnessBar

import AppKit
import DDCKit
import Observation
import ServiceManagement
import SwiftUI

/// Top-level state: the list of controllable displays, display hot-plug
/// handling, and the launch-at-login setting.
@MainActor
@Observable
final class AppModel {
    private(set) var displays: [DisplayViewModel] = []
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    /// Serial-keys of displays seen since launch, so "restore last
    /// brightness" only fires when a display (re)appears, not on every
    /// manual refresh.
    private var knownDisplayKeys: Set<String> = []

    var restoreOnReconnect: Bool {
        get { UserDefaults.standard.bool(forKey: "restoreOnReconnect") }
        set { UserDefaults.standard.set(newValue, forKey: "restoreOnReconnect") }
    }

    init() {
        // Re-discover displays whenever the display configuration changes
        // (connect, disconnect, resolution change).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: nil
        ) { @Sendable _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// Rebuilds the display list and reads each display's current
    /// hardware brightness.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        do {
            let discovered = try await DisplayManager.discover()
            var viewModels: [DisplayViewModel] = []
            for display in discovered {
                guard let link = display.link else { continue }
                do {
                    let value = try await link.read(.brightness)
                    // Contrast, color preset and volume are optional;
                    // displays that reject a query get no control for it.
                    let contrastValue = try? await link.read(.contrast)
                    let presetValue = try? await link.read(.colorPreset)
                    let volumeValue = try? await link.read(.audioVolume)
                    let vm = DisplayViewModel(
                        display: display, link: link,
                        value: value, contrastValue: contrastValue,
                        presetValue: presetValue, volumeValue: volumeValue)
                    // Restore the remembered values for displays that
                    // just (re)connected, if the user opted in.
                    if restoreOnReconnect, !knownDisplayKeys.contains(vm.persistenceKey) {
                        if let saved = vm.savedBrightness, saved != value.current {
                            await vm.apply(brightness: Double(saved))
                        }
                        if let saved = vm.savedContrast,
                            let current = contrastValue?.current, saved != current {
                            await vm.apply(contrast: Double(saved))
                        }
                        if let saved = vm.savedPreset,
                            let current = presetValue?.current, saved != current {
                            await vm.select(preset: saved)
                        }
                        if let saved = vm.savedVolume,
                            let current = volumeValue?.current, saved != current {
                            await vm.apply(volume: Double(saved))
                        }
                    }
                    knownDisplayKeys.insert(vm.persistenceKey)
                    viewModels.append(vm)
                } catch {
                    lastError = "\(display.name): \(error.localizedDescription)"
                }
            }
            displays = viewModels
            if viewModels.isEmpty && lastError == nil {
                lastError = "No DDC-capable external displays found."
            }
        } catch {
            displays = []
            lastError = error.localizedDescription
        }
    }

    // MARK: - Launch at login

    /// Launch-at-login requires a real .app bundle (SMAppService registers
    /// the bundle). When running as a bare SwiftPM binary the toggle is
    /// disabled with an explanation.
    var canManageLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
        }
    }
}
