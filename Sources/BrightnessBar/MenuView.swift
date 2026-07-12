//  MenuView.swift
//  BrightnessBar

import SwiftUI

/// Content of the menu bar popover: one native slider per display,
/// settings, and quit.
struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let error = model.lastError, model.displays.isEmpty {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }

            ForEach(model.displays) { display in
                DisplaySliderRow(viewModel: display)
            }

            Divider()

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(!model.canManageLaunchAtLogin)
            .help(model.canManageLaunchAtLogin
                ? "Start BrightnessBar automatically when you log in"
                : "Run the bundled BrightnessBar.app (Scripts/make-app.sh) to enable launch at login")

            Toggle("Restore brightness on reconnect", isOn: Binding(
                get: { model.restoreOnReconnect },
                set: { model.restoreOnReconnect = $0 }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("When a display reconnects, reapply the last brightness set from this app")

            Divider()

            HStack {
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
                Spacer()
                Text("DDC/CI hardware control")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 300)
        .task {
            // Re-sync with the hardware every time the menu opens; the
            // monitor's physical buttons may have changed the value.
            for display in model.displays {
                await display.sync()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("External Display Brightness")
                .font(.headline)
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isRefreshing)
            .help("Re-scan displays")
        }
    }
}

/// A single display's name, value and native brightness slider.
struct DisplaySliderRow: View {
    @Bindable var viewModel: DisplayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(viewModel.name)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(viewModel.brightness))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.brightness },
                    set: { viewModel.sliderMoved(to: $0) }
                ),
                in: 0...viewModel.maximum
            ) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
            }

            if let volume = viewModel.volume {
                HStack {
                    Text("Volume")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(volume))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                Slider(
                    value: Binding(
                        get: { viewModel.volume ?? 0 },
                        set: { viewModel.volumeSliderMoved(to: $0) }
                    ),
                    in: 0...viewModel.volumeMaximum
                ) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "speaker")
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
