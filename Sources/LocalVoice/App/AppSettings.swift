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

    init() {
        let rawMode = UserDefaults.standard.string(forKey: "mode") ?? ""
        self.mode = AppMode(rawValue: rawMode) ?? .directTranscription
        self.ollamaModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? DeviceCapability.recommendedGemmaModel
        self.whisperModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "base"
        let saved = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        self.hotkeyKeyCode = saved > 0 ? UInt16(saved) : 63
        let rawLang = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? ""
        self.transcriptionLanguage = TranscriptionLanguage(rawValue: rawLang) ?? .auto
        self.saveTranscribedText = UserDefaults.standard.bool(forKey: "saveTranscribedText")
    }
}
