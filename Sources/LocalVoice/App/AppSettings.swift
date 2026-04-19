import Foundation

enum AppMode: String, Codable, CaseIterable {
    case directTranscription = "Direct Transcription"
    case llmRewrite = "LLM Rewrite"
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

    init() {
        let rawMode = UserDefaults.standard.string(forKey: "mode") ?? ""
        self.mode = AppMode(rawValue: rawMode) ?? .directTranscription
        self.ollamaModel = UserDefaults.standard.string(forKey: "ollamaModel") ?? DeviceCapability.recommendedGemmaModel
        self.whisperModel = UserDefaults.standard.string(forKey: "whisperModel") ?? "base"
        let saved = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        self.hotkeyKeyCode = saved > 0 ? UInt16(saved) : 63 // F5 default
    }
}
