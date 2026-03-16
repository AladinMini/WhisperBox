import SwiftUI

struct MenuBarView: View {
    @Bindable var controller: WhisperBoxController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .fill(controller.menuBarColor)
                    .frame(width: 8, height: 8)
                Text(controller.state.statusText)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Audio Level Meter (always show when testing or active)
            if controller.state.isActive || controller.audioEngine.isRunning || controller.deviceManager.isTesting {
                AudioLevelView(level: controller.deviceManager.isTesting ? controller.deviceManager.testLevel : controller.audioEngine.audioLevel)
                    .padding(.horizontal, 12)
            }

            Divider()

            // Input Device Selector
            HStack {
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { controller.deviceManager.selectedDeviceID ?? 0 },
                    set: { newID in
                        controller.deviceManager.selectedDeviceID = newID
                    }
                )) {
                    ForEach(controller.deviceManager.availableDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)

            // Test / Refresh buttons
            HStack(spacing: 8) {
                Button(action: {
                    if controller.deviceManager.isTesting {
                        controller.deviceManager.stopTest()
                    } else {
                        controller.deviceManager.startTest()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: controller.deviceManager.isTesting ? "stop.fill" : "waveform")
                        Text(controller.deviceManager.isTesting ? "Stop Test" : "Test Mic")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    controller.deviceManager.refreshDevices()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .help("Refresh device list")

                Spacer()
            }
            .padding(.horizontal, 12)

            Divider()

            // Mode Toggle
            HStack {
                Text("Mode:")
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { controller.settings.recordingMode },
                    set: { newMode in
                        if controller.audioEngine.isRunning {
                            controller.stopLiveMode()
                        }
                        controller.settings.recordingMode = newMode
                    }
                )) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            .padding(.horizontal, 12)

            // Mode-specific controls
            if controller.settings.recordingMode == .hotkey {
                HStack {
                    Image(systemName: "keyboard")
                        .foregroundStyle(.secondary)
                    Text("⌥ Space to record")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
            } else {
                // Live mode controls
                VStack(alignment: .leading, spacing: 6) {
                    Button(action: { controller.toggleLiveMode() }) {
                        HStack {
                            Image(systemName: controller.audioEngine.isRunning ? "stop.circle.fill" : "play.circle.fill")
                            Text(controller.audioEngine.isRunning ? "Stop Listening" : "Start Listening")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(controller.audioEngine.isRunning ? .red : .green)

                    SliderRow(
                        label: "Threshold",
                        value: Binding(
                            get: { controller.settings.liveThreshold },
                            set: { controller.settings.liveThreshold = $0 }
                        ),
                        range: 0.005...0.15,
                        format: "%.3f"
                    )

                    SliderRow(
                        label: "Min Speech",
                        value: Binding(
                            get: { Float(controller.settings.minimumSpeechDuration) },
                            set: { controller.settings.minimumSpeechDuration = Double($0) }
                        ),
                        range: 0.3...2.0,
                        format: "%.1fs"
                    )

                    SliderRow(
                        label: "Silence",
                        value: Binding(
                            get: { Float(controller.settings.silenceTimeout) },
                            set: { controller.settings.silenceTimeout = Double($0) }
                        ),
                        range: 0.5...3.0,
                        format: "%.1fs"
                    )
                }
                .padding(.horizontal, 12)
            }

            Divider()

            // Toggles
            Toggle("Claude Cleanup", isOn: Binding(
                get: { controller.settings.enableClaudeCleanup },
                set: { controller.settings.enableClaudeCleanup = $0 }
            ))
            .padding(.horizontal, 12)

            Toggle("Auto-Paste", isOn: Binding(
                get: { controller.settings.autoPasteEnabled },
                set: { controller.settings.autoPasteEnabled = $0 }
            ))
            .padding(.horizontal, 12)

            // Model status
            if controller.modelManager.isDownloading {
                HStack {
                    ProgressView(value: controller.modelManager.downloadProgress)
                    Text("\(Int(controller.modelManager.downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
            } else if !controller.modelManager.isModelReady {
                Button("Download Whisper Model") {
                    Task {
                        try? await controller.modelManager.downloadModelIfNeeded()
                        try? await controller.transcriptionService.loadModel(from: controller.modelManager.modelFileURL)
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider()

            // Recent Transcriptions
            if !controller.recentTranscriptions.isEmpty {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                ForEach(controller.recentTranscriptions.prefix(5)) { t in
                    Button(action: {
                        ClipboardManager.copyToClipboard(t.displayText)
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.displayText)
                                .lineLimit(2)
                                .font(.caption)
                            Text(t.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }

                Divider()
            }

            // Bottom actions
            HStack {
                SettingsLink {
                    Text("Settings...")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 300)
    }
}

// MARK: - Subviews

struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(levelColor)
                    .frame(width: max(0, geo.size.width * CGFloat(min(level * 5, 1.0))))
            }
        }
        .frame(height: 6)
    }

    private var levelColor: Color {
        if level > 0.1 { return .red }
        if level > 0.05 { return .yellow }
        return .green
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Slider(value: $value, in: range)
                .frame(maxWidth: .infinity)
            Text(String(format: format, value))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 45, alignment: .trailing)
        }
    }
}
