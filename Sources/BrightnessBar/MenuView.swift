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

            if let contrast = viewModel.contrast {
                HStack {
                    Text("Contrast")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(contrast))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Int(contrast) == Int(viewModel.contrastMidpoint) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                }
                .padding(.top, 4)
                Slider(
                    value: Binding(
                        get: { viewModel.contrast ?? 0 },
                        set: { viewModel.contrastSliderMoved(to: $0) }
                    ),
                    in: 0...viewModel.contrastMaximum
                ) {
                    EmptyView()
                } minimumValueLabel: {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                        .opacity(0.45)
                } maximumValueLabel: {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                        .opacity(1.0)
                }
                // Center tick marking the neutral (detent) position.
                .background {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.tertiary)
                        .frame(width: 2, height: 10)
                }
            }

            if viewModel.colorPreset != nil {
                HStack {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 4)
                HStack(spacing: 6) {
                    ForEach(ColorPreset.all) { preset in
                        PresetButton(
                            preset: preset,
                            isActive: viewModel.colorPreset == preset.value
                        ) {
                            Task { await viewModel.select(preset: preset.value) }
                        }
                    }
                }
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

/// One color-temperature preset button; the active preset is tinted with
/// the accent color.
struct PresetButton: View {
    let preset: ColorPreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(preset.label)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? Color.accentColor : nil)
        .controlSize(.small)
        .help(preset.detail)
    }
}
