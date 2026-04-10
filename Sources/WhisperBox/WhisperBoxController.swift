import Foundation
import SwiftUI

@Observable
final class WhisperBoxController {
    let settings = AppSettings()
    let audioEngine = AudioEngine()
    let transcriptionService = TranscriptionService()
    let modelManager = ModelManager()
    let hotkeyManager = HotkeyManager()
    let claudeService = ClaudeAPIService()
    let deviceManager = AudioDeviceManager()
    let voiceChatService = VoiceChatService()
    let streamingVoiceChat = StreamingVoiceChatService()
    private var _transcriptOverlay: TranscriptOverlayWindow?
    @MainActor var transcriptOverlay: TranscriptOverlayWindow {
        if _transcriptOverlay == nil { _transcriptOverlay = TranscriptOverlayWindow() }
        return _transcriptOverlay!
    }

    var state: RecordingState = .idle
    var recentTranscriptions: [Transcription] = []

    var menuBarIcon: String {
        switch state {
        case .recording: return "waveform.circle.fill"
        case .listening: return "ear.fill"
        case .transcribing, .cleaning: return "ellipsis.circle.fill"
        case .thinking: return "brain"
        case .speaking: return "speaker.wave.3.fill"
        default:
            if settings.recordingMode == .voiceChat { return "bubble.left.and.bubble.right.fill" }
            return settings.recordingMode == .live && audioEngine.isRunning
                ? "ear.fill" : "waveform.circle"
        }
    }

    var menuBarColor: Color {
        switch state {
        case .recording: return .green
        case .listening: return .yellow
        case .transcribing, .cleaning: return .orange
        case .thinking: return .purple
        case .speaking: return .blue
        case .error: return .red
        default:
            if settings.recordingMode == .voiceChat { return .purple }
            return settings.recordingMode == .live && audioEngine.isRunning
                ? .yellow : .primary
        }
    }

    init() {
        setupHotkey()
        Task { await loadModel() }
    }

    // MARK: - Setup

    private func setupHotkey() {
        hotkeyManager.configuredKeyCode = settings.hotkeyCode
        hotkeyManager.configuredModifiers = settings.hotkeyModifiers
        hotkeyManager.onToggle = { [weak self] in
            self?.toggleHotkeyRecording()
        }
        hotkeyManager.start()
    }

    func updateHotkey() {
        hotkeyManager.stop()
        hotkeyManager.configuredKeyCode = settings.hotkeyCode
        hotkeyManager.configuredModifiers = settings.hotkeyModifiers
        hotkeyManager.start()
    }

    private func loadModel() async {
        do {
            try await modelManager.downloadModelIfNeeded()
            try await transcriptionService.loadModel(from: modelManager.modelFileURL)
        } catch {
            state = .error("Model load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Hotkey Mode

    func toggleHotkeyRecording() {
        if settings.recordingMode == .voiceChat {
            toggleVoiceChatRecording()
            return
        }

        guard settings.recordingMode == .hotkey else { return }

        switch state {
        case .idle, .done, .error:
            startRecording()
        case .recording:
            stopRecordingAndProcess()
        default:
            break
        }
    }

    private func startRecording() {
        do {
            try audioEngine.startBufferedCapture(deviceManager: deviceManager)
            state = .recording
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func stopRecordingAndProcess() {
        let buffer = audioEngine.stopAndReturnBuffer()
        guard !buffer.isEmpty else {
            state = .idle
            return
        }
        Task { await processAudio(buffer) }
    }

    // MARK: - Live Mode

    func startLiveMode() {
        guard !audioEngine.isRunning else { return }
        do {
            try audioEngine.startLiveCapture(
                threshold: settings.liveThreshold,
                silenceTimeout: settings.silenceTimeout,
                minimumDuration: settings.minimumSpeechDuration,
                deviceManager: deviceManager
            ) { [weak self] buffer in
                guard let self else { return }
                Task { @MainActor in
                    await self.processAudio(buffer)
                }
            }
            state = .listening
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func stopLiveMode() {
        audioEngine.stop()
        state = .idle
    }

    func toggleLiveMode() {
        if audioEngine.isRunning {
            stopLiveMode()
        } else {
            startLiveMode()
        }
    }

    // MARK: - Voice Chat Mode

    func toggleVoiceChatRecording() {
        switch state {
        case .idle, .done, .error:
            startRecording()
        case .recording:
            stopRecordingAndChat()
        case .speaking:
            streamingVoiceChat.stopPlayback()
            state = .idle
        default:
            break
        }
    }

    private func stopRecordingAndChat() {
        let buffer = audioEngine.stopAndReturnBuffer()
        guard !buffer.isEmpty else {
            state = .idle
            return
        }
        Task { await processVoiceChat(buffer) }
    }

    @MainActor
    private func processVoiceChat(_ buffer: [Float]) async {
        guard transcriptionService.isLoaded else {
            state = .error("Model not loaded yet")
            return
        }

        state = .transcribing

        do {
            let rawText = try await transcriptionService.transcribe(audioFrames: buffer)
            guard !rawText.isEmpty else {
                state = .idle
                return
            }

            state = .thinking

            transcriptOverlay.style = settings.overlayStyle
            transcriptOverlay.show(userText: rawText)

            streamingVoiceChat.voiceName = settings.kokoroVoice
            streamingVoiceChat.outputDeviceID = deviceManager.selectedOutputDeviceID
            await streamingVoiceChat.sendAndSpeak(
                transcript: rawText,
                onPartialResponse: { [weak self] partial in
                    self?.transcriptOverlay.updateResponse(partial)
                },
                onStartSpeaking: { [weak self] in
                    self?.state = .speaking
                },
                onFinished: { [weak self] in
                    self?.state = .idle
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        self?.transcriptOverlay.hide()
                    }
                }
            )
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Processing Pipeline

    @MainActor
    private func processAudio(_ buffer: [Float]) async {
        guard transcriptionService.isLoaded else {
            state = .error("Model not loaded yet")
            return
        }

        state = .transcribing

        do {
            var rawText = try await transcriptionService.transcribe(audioFrames: buffer)

            // Filter out Whisper artifacts
            let artifacts = ["[BLANK_AUDIO]", "[silence]", "[music]", "[applause]", "[laughter]", "(silence)", "(music)"]
            for artifact in artifacts {
                rawText = rawText.replacingOccurrences(of: artifact, with: "")
            }
            rawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !rawText.isEmpty else {
                state = settings.recordingMode == .live ? .listening : .idle
                return
            }

            var cleanedText: String? = nil

            if settings.enableClaudeCleanup {
                state = .cleaning
                cleanedText = try? await claudeService.cleanup(
                    rawTranscript: rawText,
                    apiKey: settings.claudeAPIKey
                )
            }

            let transcription = Transcription(
                rawText: rawText,
                cleanedText: cleanedText,
                timestamp: Date()
            )

            recentTranscriptions.insert(transcription, at: 0)
            if recentTranscriptions.count > 10 {
                recentTranscriptions = Array(recentTranscriptions.prefix(10))
            }

            let finalText = transcription.displayText
            ClipboardManager.copyToClipboard(finalText)

            if settings.autoPasteEnabled {
                ClipboardManager.autoPaste()
            }

            state = .done(finalText)

            // In live mode, go back to listening after a brief pause
            if settings.recordingMode == .live && audioEngine.isRunning {
                try? await Task.sleep(for: .seconds(0.5))
                state = .listening
            }
        } catch {
            state = .error(error.localizedDescription)
            if settings.recordingMode == .live && audioEngine.isRunning {
                try? await Task.sleep(for: .seconds(2))
                state = .listening
            }
        }
    }
}
