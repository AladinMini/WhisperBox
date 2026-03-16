import Foundation

@Observable
final class ModelManager {
    var downloadProgress: Double = 0
    var isDownloading = false
    var errorMessage: String?

    private static let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!

    var isModelReady: Bool {
        FileManager.default.fileExists(atPath: AppSettings.modelFileURL.path)
    }

    var modelFileURL: URL {
        AppSettings.modelFileURL
    }

    func downloadModelIfNeeded() async throws {
        guard !isModelReady else { return }

        let directory = AppSettings.modelDirectoryURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        isDownloading = true
        downloadProgress = 0
        errorMessage = nil

        defer { isDownloading = false }

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: Self.modelURL)

        let expectedLength = response.expectedContentLength
        let tempURL = directory.appendingPathComponent("ggml-base.en.bin.download")

        // Remove any partial download
        try? FileManager.default.removeItem(at: tempURL)

        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tempURL)

        var downloaded: Int64 = 0
        var buffer = Data()
        let chunkSize = 1024 * 1024 // 1MB chunks

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                handle.write(buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expectedLength > 0 {
                    await MainActor.run {
                        self.downloadProgress = Double(downloaded) / Double(expectedLength)
                    }
                }
            }
        }

        // Write remaining bytes
        if !buffer.isEmpty {
            handle.write(buffer)
        }
        handle.closeFile()

        // Move to final location
        try? FileManager.default.removeItem(at: modelFileURL)
        try FileManager.default.moveItem(at: tempURL, to: modelFileURL)

        await MainActor.run {
            self.downloadProgress = 1.0
        }
    }
}
