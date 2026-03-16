import Foundation
import SwiftWhisper

@Observable
final class TranscriptionService {
    var isLoaded = false
    var progress: Double = 0

    private var whisper: Whisper?

    func loadModel(from url: URL) async throws {
        guard !isLoaded else { return }

        let w = Whisper(fromFileURL: url)
        w.params.language = .english
        w.params.translate = false

        self.whisper = w
        self.isLoaded = true
    }

    func transcribe(audioFrames: [Float]) async throws -> String {
        guard let whisper else {
            throw TranscriptionError.modelNotLoaded
        }

        let segments = try await whisper.transcribe(audioFrames: audioFrames)
        let text = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not loaded"
        }
    }
}
