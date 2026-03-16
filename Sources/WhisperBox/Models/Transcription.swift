import Foundation

struct Transcription: Identifiable {
    let id = UUID()
    let rawText: String
    let cleanedText: String?
    let timestamp: Date

    var displayText: String {
        cleanedText ?? rawText
    }
}
