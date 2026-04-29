import Foundation
import Hub
import MLXLLM
import MLXLMCommon
import Tokenizers

private func modelsDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LocalVoice/MLXModels", isDirectory: true)
}

private func isWrappedInQuotes(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first, let last = trimmed.last else { return false }
    switch first {
    case "\"": return last == "\""
    case "“":  return last == "”"
    case "«":  return last == "»"
    default:   return false
    }
}

@main
struct Main {
    static func main() async throws {
        let arguments = CommandLine.arguments.dropFirst()
        guard let modelID = arguments.first else {
            fputs("Usage: swift run -c release MLXSmokeTest <model-id>\n", stderr)
            exit(64)
        }

        let prompt = ProcessInfo.processInfo.environment["PROMPT"]
            ?? "Return exactly this text without quotation marks: LocalVoice smoke test passed."
        let maxTokens = Int(ProcessInfo.processInfo.environment["MAX_TOKENS"] ?? "64") ?? 64

        let started = Date()
        let container = try await loadModelContainer(
            from: HubDownloader(downloadBase: modelsDirectory()),
            using: TransformersTokenizerLoader(),
            id: String(modelID)
        )

        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(
                maxTokens: maxTokens,
                temperature: 0,
                topP: 1
            )
        )

        await session.clear()
        let generated = try await session.respond(to: prompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let elapsed = Date().timeIntervalSince(started)
        let wrapped = isWrappedInQuotes(generated)

        let result: [String: Any] = [
            "model": String(modelID),
            "elapsedSeconds": elapsed,
            "response": generated,
            "wrappedInQuotes": wrapped,
            "passed": !generated.isEmpty && !wrapped
        ]

        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))

        if generated.isEmpty || wrapped {
            exit(1)
        }
    }
}

private struct HubDownloader: MLXLMCommon.Downloader {
    private let hub: HubApi

    init(downloadBase: URL) {
        try? FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        self.hub = HubApi(downloadBase: downloadBase)
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        try await hub.snapshot(
            from: id,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
