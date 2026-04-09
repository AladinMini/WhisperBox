import Foundation
import SwiftUI

enum TTSEngine: String, CaseIterable {
    case auto = "auto"
    case qwen3 = "qwen3"
    case system = "system"

    var displayName: String {
        switch self {
        case .auto: return "Auto (Qwen3 → System)"
        case .qwen3: return "Qwen3-TTS"
        case .system: return "macOS Say"
        }
    }
}

@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var recordingMode: RecordingMode {
        get { RecordingMode(rawValue: defaults.string(forKey: "recordingMode") ?? "Hotkey") ?? .hotkey }
        set { defaults.set(newValue.rawValue, forKey: "recordingMode") }
    }

    var claudeAPIKey: String {
        get { defaults.string(forKey: "claudeAPIKey") ?? "" }
        set { defaults.set(newValue, forKey: "claudeAPIKey") }
    }

    var enableClaudeCleanup: Bool {
        get { defaults.object(forKey: "enableClaudeCleanup") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "enableClaudeCleanup") }
    }

    var autoPasteEnabled: Bool {
        get { defaults.object(forKey: "autoPasteEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "autoPasteEnabled") }
    }

    /// RMS threshold for live mode voice detection (0.0 - 1.0 range, maps to dB in UI)
    var liveThreshold: Float {
        get { defaults.object(forKey: "liveThreshold") as? Float ?? 0.03 }
        set { defaults.set(newValue, forKey: "liveThreshold") }
    }

    /// Minimum speech duration in seconds before processing
    var minimumSpeechDuration: Double {
        get { defaults.object(forKey: "minimumSpeechDuration") as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: "minimumSpeechDuration") }
    }

    /// Silence timeout in seconds before auto-stopping in live mode
    var silenceTimeout: Double {
        get { defaults.object(forKey: "silenceTimeout") as? Double ?? 1.5 }
        set { defaults.set(newValue, forKey: "silenceTimeout") }
    }

    /// Hotkey keycode (default 61 = Right Option)
    var hotkeyCode: Int {
        get { defaults.object(forKey: "hotkeyCode") as? Int ?? 61 }
        set { defaults.set(newValue, forKey: "hotkeyCode") }
    }

    /// Hotkey modifier flags (default 0 = no modifiers, standalone key)
    var hotkeyModifiers: Int {
        get { defaults.object(forKey: "hotkeyModifiers") as? Int ?? 0 }
        set { defaults.set(newValue, forKey: "hotkeyModifiers") }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - OpenClaw Gateway (Voice Chat)

    var gatewayURL: String {
        get { defaults.string(forKey: "gatewayURL") ?? "http://127.0.0.1:18789" }
        set { defaults.set(newValue, forKey: "gatewayURL") }
    }

    var gatewayToken: String {
        get { defaults.string(forKey: "gatewayToken") ?? "" }
        set { defaults.set(newValue, forKey: "gatewayToken") }
    }

    // MARK: - TTS

    var ttsEngine: TTSEngine {
        get { TTSEngine(rawValue: defaults.string(forKey: "ttsEngine") ?? "auto") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "ttsEngine") }
    }

    var customTTSPath: String {
        get { defaults.string(forKey: "customTTSPath") ?? "" }
        set { defaults.set(newValue, forKey: "customTTSPath") }
    }

    static var modelDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WhisperBox", isDirectory: true)
    }

    static var modelFileURL: URL {
        modelDirectoryURL.appendingPathComponent("ggml-base.en.bin")
    }
}
