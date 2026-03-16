import AVFoundation
import Foundation

@Observable
final class AudioEngine {
    var audioLevel: Float = 0
    var isRunning = false

    private var engine: AVAudioEngine?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()

    // MARK: - Hotkey Mode (buffered capture)

    func startBufferedCapture() throws {
        guard !isRunning else { return }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono Float32 (what whisper.cpp expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Calculate RMS for level meter
            let level = Self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
            }

            // Convert to 16kHz mono
            if let converted = Self.convert(buffer: buffer, converter: converter, targetFormat: targetFormat) {
                let floats = Self.extractFloats(from: converted)
                self.bufferLock.lock()
                self.audioBuffer.append(contentsOf: floats)
                self.bufferLock.unlock()
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stopAndReturnBuffer() -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false

        bufferLock.lock()
        let result = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        DispatchQueue.main.async {
            self.audioLevel = 0
        }

        return result
    }

    // MARK: - Live Mode (continuous monitoring with callback)

    func startLiveCapture(
        threshold: Float,
        silenceTimeout: TimeInterval,
        minimumDuration: TimeInterval,
        onSpeechCaptured: @escaping ([Float]) -> Void
    ) throws {
        guard !isRunning else { return }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioError.converterError
        }

        var isSpeaking = false
        var silenceStart: Date?
        var speechStart: Date?

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let level = Self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.audioLevel = level
            }

            let aboveThreshold = level > threshold

            if aboveThreshold {
                silenceStart = nil

                if !isSpeaking {
                    isSpeaking = true
                    speechStart = Date()
                }

                // Convert and buffer
                if let converted = Self.convert(buffer: buffer, converter: converter, targetFormat: targetFormat) {
                    let floats = Self.extractFloats(from: converted)
                    self.bufferLock.lock()
                    self.audioBuffer.append(contentsOf: floats)
                    self.bufferLock.unlock()
                }
            } else if isSpeaking {
                // Still buffer during silence detection window
                if let converted = Self.convert(buffer: buffer, converter: converter, targetFormat: targetFormat) {
                    let floats = Self.extractFloats(from: converted)
                    self.bufferLock.lock()
                    self.audioBuffer.append(contentsOf: floats)
                    self.bufferLock.unlock()
                }

                if silenceStart == nil {
                    silenceStart = Date()
                }

                if let start = silenceStart,
                   Date().timeIntervalSince(start) >= silenceTimeout {
                    // Silence timeout reached - process if minimum duration met
                    isSpeaking = false
                    silenceStart = nil

                    let duration = speechStart.map { Date().timeIntervalSince($0) } ?? 0

                    self.bufferLock.lock()
                    let captured = self.audioBuffer
                    self.audioBuffer.removeAll()
                    self.bufferLock.unlock()

                    if duration >= minimumDuration && !captured.isEmpty {
                        onSpeechCaptured(captured)
                    }

                    speechStart = nil
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false

        DispatchQueue.main.async {
            self.audioLevel = 0
        }
    }

    // MARK: - Helpers

    private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<frames {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        return sqrt(sum / Float(frames))
    }

    private static func convert(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        var hasData = true
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                outStatus.pointee = .haveData
                hasData = false
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if error != nil { return nil }
        return outputBuffer
    }

    private static func extractFloats(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frames))
    }
}

enum AudioError: LocalizedError {
    case formatError
    case converterError
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to create audio format"
        case .converterError: return "Failed to create audio converter"
        case .permissionDenied: return "Microphone permission denied"
        }
    }
}
