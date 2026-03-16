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

    func startBufferedCapture(deviceManager: AudioDeviceManager? = nil) throws {
        guard !isRunning else { return }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        let engine = AVAudioEngine()
        self.engine = engine

        // Apply selected input device
        deviceManager?.applySelectedDevice(to: engine)

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
        deviceManager: AudioDeviceManager? = nil,
        onSpeechCaptured: @escaping ([Float]) -> Void
    ) throws {
        guard !isRunning else { return }

        bufferLock.lock()
        audioBuffer.removeAll()
        bufferLock.unlock()

        let engine = AVAudioEngine()
        self.engine = engine

        // Apply selected input device
        deviceManager?.applySelectedDevice(to: engine)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Use native format for capturing — convert when delivering
        let nativeSampleRate = inputFormat.sampleRate
        let nativeChannels = inputFormat.channelCount

        var isSpeaking = false
        var silenceStart: Date?
        var speechStart: Date?
        var rawBuffer: [Float] = []
        let rawLock = NSLock()
        var isProcessing = false

        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self, !isProcessing else { return }

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
                    print("[Live] Speech detected (level: \(String(format: "%.4f", level)))")
                }

                // Buffer raw audio
                let floats = Self.extractFloats(from: buffer)
                rawLock.lock()
                rawBuffer.append(contentsOf: floats)
                rawLock.unlock()

            } else if isSpeaking {
                // Keep buffering during silence window
                let floats = Self.extractFloats(from: buffer)
                rawLock.lock()
                rawBuffer.append(contentsOf: floats)
                rawLock.unlock()

                if silenceStart == nil {
                    silenceStart = Date()
                }

                if let start = silenceStart,
                   Date().timeIntervalSince(start) >= silenceTimeout {

                    isSpeaking = false
                    silenceStart = nil
                    let duration = speechStart.map { Date().timeIntervalSince($0) } ?? 0

                    rawLock.lock()
                    let captured = rawBuffer
                    rawBuffer.removeAll()
                    rawLock.unlock()

                    speechStart = nil

                    print("[Live] Silence detected. Duration: \(String(format: "%.1f", duration))s, Samples: \(captured.count)")

                    if duration >= minimumDuration && !captured.isEmpty {
                        // Resample to 16kHz mono
                        let resampled = Self.resampleTo16kMono(
                            samples: captured,
                            fromSampleRate: nativeSampleRate,
                            fromChannels: Int(nativeChannels)
                        )
                        print("[Live] Resampled: \(resampled.count) samples, sending to transcription")
                        isProcessing = true
                        DispatchQueue.main.async {
                            isProcessing = false
                            onSpeechCaptured(resampled)
                        }
                    }
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        print("[Live] Capture started. Threshold: \(threshold), Silence: \(silenceTimeout)s, Min: \(minimumDuration)s")
    }

    // Resample to 16kHz mono for Whisper
    private static func resampleTo16kMono(samples: [Float], fromSampleRate: Double, fromChannels: Int) -> [Float] {
        // Mix to mono if stereo
        var mono: [Float]
        if fromChannels > 1 {
            let frameCount = samples.count / fromChannels
            mono = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                var sum: Float = 0
                for ch in 0..<fromChannels {
                    sum += samples[i * fromChannels + ch]
                }
                mono[i] = sum / Float(fromChannels)
            }
        } else {
            mono = samples
        }

        // Resample to 16kHz
        let ratio = 16000.0 / fromSampleRate
        if abs(ratio - 1.0) < 0.01 { return mono } // Already 16kHz

        let outputCount = Int(Double(mono.count) * ratio)
        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIdx = Double(i) / ratio
            let idx = Int(srcIdx)
            let frac = Float(srcIdx - Double(idx))
            if idx + 1 < mono.count {
                output[i] = mono[idx] * (1 - frac) + mono[idx + 1] * frac
            } else if idx < mono.count {
                output[i] = mono[idx]
            }
        }
        return output
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
