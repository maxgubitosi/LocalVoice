import WhisperKit
import Foundation

final class TranscriptionEngine {
    private var whisper: WhisperKit?
    private var currentModel: String = "base"

    func loadModel(named model: String = "openai_whisper-large-v3_turbo") async {
        currentModel = model
        let name = TranscriptionEngine.displayName(for: model)
        do {
            let modelDir = try modelDirectory()
            if !modelAlreadyDownloaded(model, in: modelDir) {
                print("[TranscriptionEngine] Downloading '\(name)' for the first time — this may take a minute...")
            }
            print("[TranscriptionEngine] Loading model '\(name)'...")
            whisper = try await WhisperKit(model: model, downloadBase: modelDir)
            print("[TranscriptionEngine] Ready.")
        } catch {
            print("[TranscriptionEngine] Failed to load model '\(name)': \(error)")
        }
    }

    private func modelAlreadyDownloaded(_ model: String, in dir: URL) -> Bool {
        let coreMLDir = dir.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: coreMLDir.path)) ?? []
        return contents.contains { $0.localizedCaseInsensitiveContains(model) }
    }

    private func modelDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("LocalVoice/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func transcribe(buffer: [Float], language: String? = nil) async throws -> TranscriptionOutput {
        guard let whisper else {
            throw TranscriptionError.modelNotLoaded
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true
        )

        let results = try await whisper.transcribe(audioArray: buffer, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return TranscriptionOutput(text: text, language: results.first?.language)
    }

    // MARK: - Available models

    static let availableModels = ["tiny", "base", "small", "medium", "openai_whisper-large-v3_turbo", "large-v3"]

    static let modelDisplayNames: [String: String] = [
        "openai_whisper-large-v3_turbo": "large-v3-turbo",
    ]

    static func displayName(for model: String) -> String {
        modelDisplayNames[model] ?? model
    }
}

struct TranscriptionOutput {
    let text: String
    let language: String?
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not yet loaded. Please wait a moment."
        }
    }
}
