import SwiftUI

struct SettingsView: View {
    @Bindable var controller: WhisperBoxController
    @State private var apiKeyVisible = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            apiTab
                .tabItem {
                    Label("API", systemImage: "key")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Section("Recording") {
                Picker("Default Mode", selection: Binding(
                    get: { controller.settings.recordingMode },
                    set: { controller.settings.recordingMode = $0 }
                )) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Auto-paste after transcription", isOn: Binding(
                    get: { controller.settings.autoPasteEnabled },
                    set: { controller.settings.autoPasteEnabled = $0 }
                ))

                Toggle("Claude cleanup", isOn: Binding(
                    get: { controller.settings.enableClaudeCleanup },
                    set: { controller.settings.enableClaudeCleanup = $0 }
                ))
            }

            Section("Live Mode") {
                HStack {
                    Text("Threshold")
                    Slider(
                        value: Binding(
                            get: { controller.settings.liveThreshold },
                            set: { controller.settings.liveThreshold = $0 }
                        ),
                        in: 0.005...0.15
                    )
                    Text(String(format: "%.3f", controller.settings.liveThreshold))
                        .monospacedDigit()
                        .frame(width: 50)
                }

                HStack {
                    Text("Min Speech")
                    Slider(
                        value: Binding(
                            get: { controller.settings.minimumSpeechDuration },
                            set: { controller.settings.minimumSpeechDuration = $0 }
                        ),
                        in: 0.3...2.0
                    )
                    Text(String(format: "%.1fs", controller.settings.minimumSpeechDuration))
                        .monospacedDigit()
                        .frame(width: 50)
                }

                HStack {
                    Text("Silence Timeout")
                    Slider(
                        value: Binding(
                            get: { controller.settings.silenceTimeout },
                            set: { controller.settings.silenceTimeout = $0 }
                        ),
                        in: 0.5...3.0
                    )
                    Text(String(format: "%.1fs", controller.settings.silenceTimeout))
                        .monospacedDigit()
                        .frame(width: 50)
                }
            }

            Section("Accessibility") {
                HStack {
                    if HotkeyManager.checkAccessibilityPermission() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Accessibility access granted")
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Accessibility access needed for hotkey")
                        Button("Request") {
                            HotkeyManager.requestAccessibilityPermission()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var apiTab: some View {
        Form {
            Section("Anthropic Claude API") {
                HStack {
                    if apiKeyVisible {
                        TextField("API Key", text: Binding(
                            get: { controller.settings.claudeAPIKey },
                            set: { controller.settings.claudeAPIKey = $0 }
                        ))
                    } else {
                        SecureField("API Key", text: Binding(
                            get: { controller.settings.claudeAPIKey },
                            set: { controller.settings.claudeAPIKey = $0 }
                        ))
                    }
                    Button(apiKeyVisible ? "Hide" : "Show") {
                        apiKeyVisible.toggle()
                    }
                    .frame(width: 50)
                }

                Text("Get your API key from console.anthropic.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if controller.settings.claudeAPIKey.isEmpty {
                    Label("No API key — Claude cleanup disabled", systemImage: "info.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                } else {
                    Label("Claude cleanup ready", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("WhisperBox")
                .font(.title)
                .fontWeight(.bold)

            Text("v1.0")
                .foregroundStyle(.secondary)

            Text("Local speech-to-text with optional Claude cleanup")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Text("Built with whisper.cpp + Claude API")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
    }
}
