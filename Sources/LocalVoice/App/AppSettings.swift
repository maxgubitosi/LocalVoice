import Foundation

enum AppMode: String, Codable, CaseIterable {
    case directTranscription = "Direct Transcription"
    case llmRewrite = "Refine"
}

enum TranscriptionLanguage: String, Codable, CaseIterable {
    case auto    = "Auto"
    case system  = "System"
    case english = "English"
    case spanish = "Spanish"

    var whisperCode: String? {
        switch self {
        case .auto:    return nil
        case .english: return "en"
        case .spanish: return "es"
        case .system:
            let tag = Locale.preferredLanguages.first ?? ""
            let code = Locale.Language(identifier: tag).languageCode?.identifier ?? ""
            return code.isEmpty ? nil : code
        }
    }

    var displayName: String {
        switch self {
        case .auto:    return "Auto"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .system:
            let tag = Locale.preferredLanguages.first ?? ""
            let code = Locale.Language(identifier: tag).languageCode?.identifier ?? ""
            if let name = code.isEmpty ? nil : Locale.current.localizedString(forLanguageCode: code) {
                return "System (\(name))"
            }
            return "System"
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var mode: AppMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    @Published var llmModel: String {
        didSet { UserDefaults.standard.set(llmModel, forKey: "llmModel") }
    }
    @Published var whisperModel: String {
        didSet { UserDefaults.standard.set(whisperModel, forKey: "whisperModel") }
    }
    @Published var recordingHotkey: RecordingHotkey {
        didSet { UserDefaults.standard.set(recordingHotkey.rawValue, forKey: "recordingHotkey") }
    }
    @Published var transcriptionLanguage: TranscriptionLanguage {
        didSet { UserDefaults.standard.set(transcriptionLanguage.rawValue, forKey: "transcriptionLanguage") }
    }
    @Published var saveTranscribedText: Bool {
        didSet { UserDefaults.standard.set(saveTranscribedText, forKey: "saveTranscribedText") }
    }
    @Published var activePromptID: UUID? {
        didSet { UserDefaults.standard.set(activePromptID?.uuidString, forKey: "activePromptID") }
    }

    // Maps legacy/incorrect model names to their canonical WhisperKit identifiers.
    private static let modelMigrations: [String: String] = [
        "large-v3-turbo": "openai_whisper-large-v3_turbo",
    ]

    private static let llmModelMigrations: [String: String] = [
        "mlx-community/Qwen3.5-2B-MLX-4bit": "mlx-community/Qwen3.5-2B-OptiQ-4bit",
        "mlx-community/Qwen3.5-4B-MLX-4bit": "mlx-community/gemma-4-e2b-it-4bit",
        "mlx-community/Qwen3.5-9B-MLX-4bit": "mlx-community/gemma-4-e4b-it-4bit",
        "mlx-community/Qwen3.5-27B-4bit": "mlx-community/gemma-4-e4b-it-4bit",
        "mlx-community/Qwen3-1.7B-4bit": "mlx-community/Qwen3.5-2B-OptiQ-4bit",
        "mlx-community/Qwen3-4B-4bit": "mlx-community/gemma-4-e2b-it-4bit",
        "mlx-community/Qwen3-8B-4bit": "mlx-community/gemma-4-e4b-it-4bit",
        "mlx-community/gemma-3n-E2B-it-lm-4bit": "mlx-community/gemma-4-e2b-it-4bit",
        "mlx-community/gemma-3n-E4B-it-lm-4bit": "mlx-community/gemma-4-e4b-it-4bit",
        "mlx-community/Llama-3.2-3B-Instruct-4bit": "mlx-community/Phi-4-mini-instruct-4bit",
    ]

    init() {
        let rawMode = UserDefaults.standard.string(forKey: "mode") ?? ""
        let migratedMode = rawMode == "LLM Rewrite" ? "Refine" : rawMode
        self.mode = AppMode(rawValue: migratedMode) ?? .directTranscription
        let savedLLMModel = UserDefaults.standard.string(forKey: "llmModel")
            ?? UserDefaults.standard.string(forKey: "ollamaModel")
        let migratedLLMModel = savedLLMModel.map { AppSettings.llmModelMigrations[$0] ?? $0 }
        if let migratedLLMModel, MLXModelCatalog.model(id: migratedLLMModel) != nil {
            self.llmModel = migratedLLMModel
        } else {
            self.llmModel = DeviceCapability.recommendedMLXModel
        }
        let savedModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "openai_whisper-large-v3_turbo"
        self.whisperModel = AppSettings.modelMigrations[savedModel] ?? savedModel
        if let rawHotkey = UserDefaults.standard.string(forKey: "recordingHotkey"),
           let savedHotkey = RecordingHotkey(rawValue: rawHotkey) {
            self.recordingHotkey = savedHotkey
        } else {
            let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
            let migratedHotkey = RecordingHotkey.fromLegacyKeyCode(UInt16(savedKeyCode)) ?? .rightCommand
            self.recordingHotkey = migratedHotkey
            UserDefaults.standard.set(migratedHotkey.rawValue, forKey: "recordingHotkey")
        }
        let rawLang = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? ""
        self.transcriptionLanguage = TranscriptionLanguage(rawValue: rawLang) ?? .system
        self.saveTranscribedText = UserDefaults.standard.bool(forKey: "saveTranscribedText")
        let savedPromptID = UserDefaults.standard.string(forKey: "activePromptID")
        self.activePromptID = savedPromptID.flatMap { UUID(uuidString: $0) }
    }
}
