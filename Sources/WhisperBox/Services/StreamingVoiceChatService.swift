import AVFoundation
import Foundation

@Observable
final class StreamingVoiceChatService: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var isSpeaking = false
    var conversationHistory: [[String: String]] = []
    var lastResponse: String = ""
    var currentPartial: String = ""

    private var audioPlayer: AVAudioPlayer?
    private var speechQueue: [String] = []
    private var isSpeakingQueue = false
    private var playbackContinuation: CheckedContinuation<Void, Never>?

    func sendAndSpeak(
        transcript: String,
        onStartSpeaking: (() -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) async {
        conversationHistory.append(["role": "user", "content": transcript])
        if conversationHistory.count > 20 {
            conversationHistory = Array(conversationHistory.suffix(20))
        }

        lastResponse = ""
        currentPartial = ""
        speechQueue.removeAll()

        do {
            try await streamFromGateway(
                onSentence: { [weak self] sentence in
                    guard let self else { return }
                    self.speechQueue.append(sentence)
                    if !self.isSpeakingQueue {
                        self.isSpeakingQueue = true
                        Task { @MainActor in
                            onStartSpeaking?()
                            await self.processSpeechQueue()
                        }
                    }
                },
                onComplete: { [weak self] fullText in
                    guard let self else { return }
                    self.lastResponse = fullText
                    self.conversationHistory.append(["role": "assistant", "content": fullText])
                }
            )

            while isSpeakingQueue {
                try? await Task.sleep(for: .milliseconds(100))
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
        speechQueue.removeAll()
        isSpeakingQueue = false
        isSpeaking = false
        isPlaying = false
        playbackContinuation?.resume()
        playbackContinuation = nil
    }

    func clearHistory() {
        conversationHistory.removeAll()
        lastResponse = ""
        currentPartial = ""
    }

    // MARK: - Streaming Gateway

    private func streamFromGateway(
        onSentence: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void
    ) async throws {
        let configPath = "\(NSHomeDirectory())/.openclaw/openclaw.json"
        let configData = try Data(contentsOf: URL(fileURLWithPath: configPath))
        let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any] ?? [:]
        let gateway = config["gateway"] as? [String: Any] ?? [:]
        let port = gateway["port"] as? Int ?? 18789
        let auth = gateway["auth"] as? [String: Any] ?? [:]
        let token = auth["token"] as? String ?? ""

        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        request.timeoutInterval = 60

        var messages: [[String: String]] = [
            ["role": "system", "content": "You are a voice assistant. Keep responses concise and conversational — 1-3 sentences. No markdown, no formatting, no emoji — just natural speech."]
        ]
        messages.append(contentsOf: conversationHistory)

        let body: [String: Any] = [
            "model": "openclaw",
            "messages": messages,
            "max_tokens": 1024,
            "stream": true,
            "user": "whisperbox-voice"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VoiceChatError.apiError("Gateway error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        var fullText = ""
        var sentenceBuffer = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let data = String(line.dropFirst(6))
            if data == "[DONE]" { break }

            guard let jsonData = data.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            fullText += content
            sentenceBuffer += content

            await MainActor.run {
                self.currentPartial = fullText
            }

            // Check for sentence boundaries
            let sentenceEnders: [Character] = [".", "!", "?", "\n"]
            if let lastChar = sentenceBuffer.last, sentenceEnders.contains(lastChar) {
                let sentence = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    onSentence(sentence)
                }
                sentenceBuffer = ""
            }
        }

        let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            onSentence(remaining)
        }

        onComplete(fullText)
    }

    // MARK: - Speech Queue

    @MainActor
    private func processSpeechQueue() async {
        isSpeaking = true
        while !speechQueue.isEmpty {
            let sentence = speechQueue.removeFirst()
            await speakSentence(sentence)
        }
        isSpeaking = false
        isSpeakingQueue = false
    }

    @MainActor
    private func speakSentence(_ text: String) async {
        // Try Kokoro first, fall back to macOS say
        if await speakWithKokoro(text) { return }
        await speakWithSay(text)
    }

    @MainActor
    private func speakWithKokoro(_ text: String) async -> Bool {
        let outputPath = NSTemporaryDirectory() + "wb_tts_\(UUID().uuidString).mp3"
        let url = URL(string: "http://127.0.0.1:8880/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": "kokoro",
            "input": text,
            "voice": "am_puck",
            "response_format": "mp3",
            "speed": 1.0
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            try data.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            return false
        }

        await playAudioFile(outputPath)
        return true
    }

    @MainActor
    private func speakWithSay(_ text: String) async {
        let outputPath = NSTemporaryDirectory() + "wb_tts_\(UUID().uuidString).aiff"

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            process.arguments = ["-o", outputPath, "--data-format=LEF32@22050", text]
            process.terminationHandler = { _ in continuation.resume() }
            try? process.run()
        }

        guard FileManager.default.fileExists(atPath: outputPath) else { return }
        await playAudioFile(outputPath)
    }

    @MainActor
    private func playAudioFile(_ path: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                self.audioPlayer = player
                self.isPlaying = true
                self.playbackContinuation = continuation
                player.delegate = self
                player.play()
            } catch {
                self.isPlaying = false
                continuation.resume()
            }
        }

        isPlaying = false
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.playbackContinuation?.resume()
            self.playbackContinuation = nil
        }
    }
}
