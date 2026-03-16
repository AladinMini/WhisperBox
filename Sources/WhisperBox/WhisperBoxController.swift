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

    var state: RecordingState = .idle
    var recentTranscriptions: [Transcription] = []

    var menuBarIcon: String {
        switch state {
        case .recording: return "waveform.circle.fill"
        case .listening: return "ear.fill"
        case .transcribing, .cleaning: return "ellipsis.circle.fill"
        default:
            return settings.recordingMode == .live && audioEngine.isRunning
                ? "ear.fill" : "waveform.circle"
        }
    }

    var menuBarColor: Color {
        switch state {
        case .recording: return .green
        case .listening: return .yellow
        case .transcribing, .cleaning: return .orange
        case .error: return .red
        default:
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
        hotkeyManager.onToggle = { [weak self] in
            self?.toggleHotkeyRecording()
        }
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

    // MARK: - Processing Pipeline

    @MainActor
    private func processAudio(_ buffer: [Float]) async {
        guard transcriptionService.isLoaded else {
            state = .error("Model not loaded yet")
            return
        }

        state = .transcribing

        do {
            let rawText = try await transcriptionService.transcribe(audioFrames: buffer)

            guard !rawText.isEmpty else {
                state = settings.recordingMode == .live ? .listening : .idle
                return
            }

            var cleanedText: String? = nil

            if settings.enableClaudeCleanup && !settings.claudeAPIKey.isEmpty {
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
