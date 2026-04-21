import Foundation

enum AppMode: String, Codable, CaseIterable {
    case directTranscription = "Direct Transcription"
    case llmRewrite = "LLM Rewrite"
}

enum TranscriptionLanguage: String, Codable, CaseIterable {
    case auto = "Auto"
    case english = "English"
    case spanish = "Spanish"

    var whisperCode: String? {
        switch self {
        case .auto:    return nil
        case .english: return "en"
        case .spanish: return "es"
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var mode: AppMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "mode") }
    }
    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: "ollamaModel") }
    }
    @Published var whisperModel: String {
        didSet { UserDefaults.standard.set(whisperModel, forKey: "whisperModel") }
    }
    @Published var hotkeyKeyCode: UInt16 {
        didSet { UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode") }
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

    init() {
        let rawMode = UserDefaults.standard.string(forKey: "mode") ?? ""
        self.mode = AppMode(rawValue: rawMode) ?? .directTranscription
        self.ollamaModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? DeviceCapability.recommendedGemmaModel
        let savedModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "openai_whisper-large-v3_turbo"
        self.whisperModel = AppSettings.modelMigrations[savedModel] ?? savedModel
        let saved = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        self.hotkeyKeyCode = saved > 0 ? UInt16(saved) : 63
        let rawLang = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? ""
        self.transcriptionLanguage = TranscriptionLanguage(rawValue: rawLang) ?? .auto
        self.saveTranscribedText = UserDefaults.standard.bool(forKey: "saveTranscribedText")
        let savedPromptID = UserDefaults.standard.string(forKey: "activePromptID")
        self.activePromptID = savedPromptID.flatMap { UUID(uuidString: $0) }
    }
}
