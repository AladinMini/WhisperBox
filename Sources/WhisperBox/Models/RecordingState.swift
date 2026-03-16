import Foundation

enum RecordingState: Equatable {
    case idle
    case recording
    case listening
    case transcribing
    case cleaning
    case thinking
    case speaking
    case done(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .recording, .listening, .transcribing, .cleaning, .thinking, .speaking:
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .cleaning: return "Cleaning up..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        case .done(let text): return text.prefix(50) + (text.count > 50 ? "..." : "")
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

enum RecordingMode: String, CaseIterable, Codable {
    case hotkey = "Hotkey"
    case live = "Live"
    case voiceChat = "Voice Chat"
}
