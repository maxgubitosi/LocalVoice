import MLXLLM
import MLXLMCommon
import Hub
import Tokenizers
import Foundation
import OSLog

final class MLXClient: ObservableObject {
    @Published private(set) var isLLMModelLoaded: Bool = false

    var modelID: String = DeviceCapability.recommendedMLXModel {
        didSet {
            if oldValue != modelID {
                isLLMModelLoaded = false
                session = nil
                loadedModelID = nil
            }
        }
    }

    private var container: ModelContainer?
    private var session: ChatSession?
    private var loadedModelID: String?

    static let modelsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LocalVoice/MLXModels", isDirectory: true)
    }()

    func rewrite(
        transcript: String,
        prompt: LLMPrompt,
        appContext: String?,
        detectedLanguage: String?
    ) async throws -> String {
        var instruction = prompt.instruction
        if let lang = detectedLanguage,
           let displayName = Locale.current.localizedString(forLanguageCode: lang) {
            instruction += "\nRespond in \(displayName). Do NOT translate."
        } else {
            instruction += "\nRespond in the same language as the user's dictation. Do NOT translate."
        }
        if let ctx = appContext {
            instruction += "\nThe user is dictating into \(ctx). Preserve appropriate terminology and conventions."
        }
        instruction += "\n\nUser's dictation: \"\(transcript)\""
        instruction += " /no_think"
        return try await generate(prompt: instruction)
    }

    func generate(prompt: String) async throws -> String {
        if loadedModelID != modelID || session == nil {
            Logger.llm.info("Loading MLX model: \(self.modelID)")
            let newContainer = try await loadModelContainer(
                from: HubDownloader(downloadBase: Self.modelsDirectory),
                using: TransformersTokenizerLoader(),
                id: modelID
            )
            container = newContainer
            session = ChatSession(newContainer)
            loadedModelID = modelID
            isLLMModelLoaded = true
            Logger.llm.info("MLX model loaded: \(self.modelID)")
        }
        guard let session else { throw MLXClientError.modelNotLoaded }
        await session.clear()
        let response = try await session.respond(to: prompt)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MLXClientError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "LLM model not loaded."
        }
    }
}

// MARK: - HubApi → MLXLMCommon.Downloader bridge

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

// MARK: - Tokenizers.AutoTokenizer → MLXLMCommon.TokenizerLoader bridge

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
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}
