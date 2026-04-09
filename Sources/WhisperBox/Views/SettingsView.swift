import SwiftUI

struct SettingsView: View {
    @Bindable var controller: WhisperBoxController
    @State private var apiKeyVisible = false
    @State private var gatewayTokenVisible = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            voiceChatTab
                .tabItem {
                    Label("Voice Chat", systemImage: "bubble.left.and.bubble.right")
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
        .frame(width: 450, height: 380)
    }

    private var generalTab: some View {
        Form {
            Section("Hotkey") {
                HotkeyRecorderView(
                    keyCode: Binding(
                        get: { controller.settings.hotkeyCode },
                        set: {
                            controller.settings.hotkeyCode = $0
                            controller.updateHotkey()
                        }
                    ),
                    modifiers: Binding(
                        get: { controller.settings.hotkeyModifiers },
                        set: {
                            controller.settings.hotkeyModifiers = $0
                            controller.updateHotkey()
                        }
                    )
                )
            }

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

    private var voiceChatTab: some View {
        Form {
            Section("OpenClaw Gateway") {
                TextField("Gateway URL", text: Binding(
                    get: { controller.settings.gatewayURL },
                    set: { controller.settings.gatewayURL = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                HStack {
                    if gatewayTokenVisible {
                        TextField("Auth Token", text: Binding(
                            get: { controller.settings.gatewayToken },
                            set: { controller.settings.gatewayToken = $0 }
                        ))
                    } else {
                        SecureField("Auth Token", text: Binding(
                            get: { controller.settings.gatewayToken },
                            set: { controller.settings.gatewayToken = $0 }
                        ))
                    }
                    Button(gatewayTokenVisible ? "Hide" : "Show") {
                        gatewayTokenVisible.toggle()
                    }
                    .frame(width: 50)
                }

                Text("Find your token in ~/.openclaw/openclaw.json → gateway.auth.token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Kokoro Voice") {
                Picker("Voice", selection: Binding(
                    get: { controller.settings.kokoroVoice },
                    set: { controller.settings.kokoroVoice = $0 }
                )) {
                    Section("American Male") {
                        Text("Adam").tag("am_adam")
                        Text("Echo").tag("am_echo")
                        Text("Eric").tag("am_eric")
                        Text("Fenrir").tag("am_fenrir")
                        Text("Liam").tag("am_liam")
                        Text("Michael").tag("am_michael")
                        Text("Onyx").tag("am_onyx")
                        Text("Puck").tag("am_puck")
                    }
                    Section("American Female") {
                        Text("Alloy").tag("af_alloy")
                        Text("Aoede").tag("af_aoede")
                        Text("Bella").tag("af_bella")
                        Text("Heart").tag("af_heart")
                        Text("Jessica").tag("af_jessica")
                        Text("Kore").tag("af_kore")
                        Text("Nicole").tag("af_nicole")
                        Text("Nova").tag("af_nova")
                        Text("River").tag("af_river")
                        Text("Sarah").tag("af_sarah")
                        Text("Sky").tag("af_sky")
                    }
                    Section("British Male") {
                        Text("Daniel").tag("bm_daniel")
                        Text("Fable").tag("bm_fable")
                        Text("George").tag("bm_george")
                        Text("Lewis").tag("bm_lewis")
                    }
                    Section("British Female") {
                        Text("Alice").tag("bf_alice")
                        Text("Emma").tag("bf_emma")
                        Text("Lily").tag("bf_lily")
                    }
                }

                Text("Preview voices at http://localhost:8880/web/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Visual Feedback") {
                Picker("Transcript Display", selection: Binding(
                    get: { controller.settings.overlayStyle },
                    set: { controller.settings.overlayStyle = $0 }
                )) {
                    ForEach(OverlayStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text("Shows what you said and the response as it streams")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text-to-Speech") {
                Picker("TTS Engine", selection: Binding(
                    get: { controller.settings.ttsEngine },
                    set: { controller.settings.ttsEngine = $0 }
                )) {
                    ForEach(TTSEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }

                TextField("Custom TTS script path (optional)", text: Binding(
                    get: { controller.settings.customTTSPath },
                    set: { controller.settings.customTTSPath = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Text("Leave empty for default (~/.openclaw/workspace/qwen3-tts/speak.py)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
