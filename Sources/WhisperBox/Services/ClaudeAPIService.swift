import Foundation

final class ClaudeAPIService {

    func cleanup(rawTranscript: String, apiKey: String) async throws -> String {
        // Route through OpenClaw gateway — no API key needed
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
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "anthropic/claude-3-5-haiku-20241022",
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": "You are a transcript cleanup assistant. Clean up the following speech-to-text transcript: Fix grammar and punctuation. Remove filler words (um, uh, like, you know). Fix obvious speech recognition errors. Preserve the original meaning and tone. Return ONLY the cleaned text, nothing else."],
                ["role": "user", "content": rawTranscript]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw ClaudeError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ClaudeError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Claude API key configured"
        case .invalidResponse: return "Invalid response from Claude API"
        case .apiError(let code, let msg): return "Claude API error (\(code)): \(msg)"
        case .parseError: return "Failed to parse Claude API response"
        }
    }
}
