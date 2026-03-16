import AVFoundation
import Foundation

@Observable
final class VoiceChatService: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var conversationHistory: [[String: String]] = []
    var lastResponse: String = ""

    private var audioPlayer: AVAudioPlayer?
    private var onPlaybackFinished: (() -> Void)?

    // Path to Qwen3-TTS (Mac Mini)
    private let ttsScript = "\(NSHomeDirectory())/.openclaw/workspace/qwen3-tts/speak.py"
    private let ttsVenv = "\(NSHomeDirectory())/.openclaw/workspace/qwen3-tts/.venv/bin/python3"

    private var hasTTS: Bool {
        FileManager.default.fileExists(atPath: ttsScript)
    }

    func sendToClaudeAndSpeak(
        transcript: String,
        apiKey: String,
        onStartSpeaking: (() -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) async {
        // Add user message to history
        conversationHistory.append(["role": "user", "content": transcript])

        // Keep last 20 messages for context
        if conversationHistory.count > 20 {
            conversationHistory = Array(conversationHistory.suffix(20))
        }

        do {
            let response = try await callClaude(apiKey: apiKey)
            lastResponse = response

            // Add assistant response to history
            conversationHistory.append(["role": "assistant", "content": response])

            await MainActor.run { onStartSpeaking?() }

            // Generate and play TTS
            if hasTTS {
                try await speakWithQwen(text: response)
            } else {
                await speakWithSystem(text: response)
            }

            await MainActor.run { onFinished?() }
        } catch {
            lastResponse = "Error: \(error.localizedDescription)"
            await MainActor.run { onFinished?() }
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    func clearHistory() {
        conversationHistory.removeAll()
        lastResponse = ""
    }

    // MARK: - Claude API

    private func callClaude(apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": """
                You are a helpful voice assistant having a real-time conversation. \
                Keep responses concise and conversational — this is spoken dialogue, not text. \
                Aim for 1-3 sentences unless the user asks for detail. \
                Don't use markdown, bullet points, or formatting — just natural speech.
                """,
            "messages": conversationHistory.map { msg in
                ["role": msg["role"]!, "content": msg["content"]!] as [String: Any]
            }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw VoiceChatError.apiError(errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw VoiceChatError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - TTS with Qwen3

    private func speakWithQwen(text: String) async throws {
        let outputPath = NSTemporaryDirectory() + "whisperbox_tts_\(UUID().uuidString).wav"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ttsVenv)
        process.arguments = [ttsScript, text, outputPath]
        process.currentDirectoryURL = URL(fileURLWithPath: ttsScript).deletingLastPathComponent()

        // Set up environment for the venv
        var env = ProcessInfo.processInfo.environment
        let venvBin = URL(fileURLWithPath: ttsVenv).deletingLastPathComponent().path
        env["PATH"] = venvBin + ":" + (env["PATH"] ?? "")
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: outputPath) else {
            // Fallback to system voice
            await speakWithSystem(text: text)
            return
        }

        // Play the wav file
        await playAudio(url: URL(fileURLWithPath: outputPath))

        // Cleanup
        try? FileManager.default.removeItem(atPath: outputPath)
    }

    // MARK: - Fallback: macOS system voice

    private func speakWithSystem(text: String) async {
        let outputPath = NSTemporaryDirectory() + "whisperbox_tts_\(UUID().uuidString).aiff"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-o", outputPath, text]

        try? process.run()
        process.waitUntilExit()

        if FileManager.default.fileExists(atPath: outputPath) {
            await playAudio(url: URL(fileURLWithPath: outputPath))
            try? FileManager.default.removeItem(atPath: outputPath)
        }
    }

    // MARK: - Audio Playback

    @MainActor
    private func playAudio(url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                self.audioPlayer = player
                self.isPlaying = true
                self.onPlaybackFinished = {
                    continuation.resume()
                }
                player.delegate = self
                player.play()
            } catch {
                self.isPlaying = false
                continuation.resume()
            }
        }
        isPlaying = false
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.onPlaybackFinished?()
            self.onPlaybackFinished = nil
        }
    }
}

enum VoiceChatError: LocalizedError {
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .apiError(let msg): return "Claude API error: \(msg)"
        case .parseError: return "Failed to parse Claude response"
        }
    }
}
