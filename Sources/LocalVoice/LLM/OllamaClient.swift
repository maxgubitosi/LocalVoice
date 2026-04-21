import Foundation

final class OllamaClient {
    private let baseURL = URL(string: "http://localhost:11434")!
    private let session: URLSession

    var model: String = DeviceCapability.recommendedGemmaModel

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    func rewrite(transcript: String, prompt: LLMPrompt, appContext: String?) async throws -> String {
        var instruction = prompt.instruction
        if let ctx = appContext {
            instruction += "\nThe user is dictating into \(ctx). Preserve appropriate terminology and conventions."
        }
        instruction += "\n\nUser's dictation: \"\(transcript)\""

        return try await generate(prompt: instruction)
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
            if httpResponse.statusCode == 404 {
                throw OllamaError.modelNotFound(model: model)
            }
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
    case modelNotFound(model: String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .invalidResponse:            return "Invalid response from Ollama"
        case .httpError(let code):        return "Ollama HTTP error: \(code)"
        case .modelNotFound(let model):   return "Model '\(model)' not pulled. Run: ollama pull \(model)"
        case .notRunning:                 return "Ollama is not running. Start it with: ollama serve"
        }
    }
}
