import Foundation

final class OllamaClient {
    private let baseURL = URL(string: "http://localhost:11434")!
    private let session: URLSession

    var model: String = "llama3.2"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    func rewrite(transcript: String) async throws -> String {
        let prompt = """
        You are a voice-to-text assistant. The user dictated the following text:

        "\(transcript)"

        Rewrite it as a clean, well-formed prompt or message. Fix grammar, punctuation, and structure.
        Remove filler words ("um", "uh", "like", "you know"). Preserve the user's intent exactly.
        Return ONLY the rewritten text, no explanations or quotation marks.
        """

        return try await generate(prompt: prompt)
    }

    func generate(prompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaRequest(model: model, prompt: prompt, stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models.map(\.name)
    }

    func isAvailable() async -> Bool {
        guard let url = URL(string: "http://localhost:11434") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Codable models

private struct OllamaRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaResponse: Decodable {
    let model: String
    let response: String
    let done: Bool
}

private struct OllamaTagsResponse: Decodable {
    struct ModelInfo: Decodable {
        let name: String
    }
    let models: [ModelInfo]
}

enum OllamaError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .invalidResponse:        return "Invalid response from Ollama"
        case .httpError(let code):    return "Ollama HTTP error: \(code)"
        case .notRunning:             return "Ollama is not running. Start it with: ollama serve"
        }
    }
}
