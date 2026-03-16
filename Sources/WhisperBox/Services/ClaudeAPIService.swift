import Foundation

final class ClaudeAPIService {
    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!

    func cleanup(rawTranscript: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
        }

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-3-5-haiku-20241022",
            "max_tokens": 1024,
            "system": """
                You are a transcript cleanup assistant. Clean up the following speech-to-text transcript:
                - Fix grammar and punctuation
                - Remove filler words (um, uh, like, you know)
                - Fix obvious speech recognition errors
                - Preserve the original meaning and tone
                - Return ONLY the cleaned text, nothing else
                """,
            "messages": [
                ["role": "user", "content": rawTranscript]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
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
