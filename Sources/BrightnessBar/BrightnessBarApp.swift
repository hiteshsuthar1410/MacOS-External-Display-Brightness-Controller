//  BrightnessBarApp.swift
//  BrightnessBar
//
//  Menu bar app exposing a native hardware-brightness slider per external
//  display, driven by DDC/CI through DDCKit.
//
//  Note: macOS provides no extension point for third-party displays inside
//  Control Center's own Display module (it only lists Apple-protocol
//  displays), so this app installs its own menu bar item instead.

import AppKit
import SwiftUI

@main
struct BrightnessBarApp: App {
    @State private var model = AppModel()

    init() {
        // Menu bar accessory: no Dock icon, no app menu.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: "sun.max.fill")
                .accessibilityLabel("External display brightness")
        }
        .menuBarExtraStyle(.window)
    }
}
