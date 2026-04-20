import WhisperKit
import Foundation

final class TranscriptionEngine {
    private var whisper: WhisperKit?
    private var currentModel: String = "base"

    func loadModel(named model: String = "base") async {
        currentModel = model
        do {
            let modelDir = try modelDirectory()
            if !modelAlreadyDownloaded(model, in: modelDir) {
                print("[TranscriptionEngine] Downloading '\(model)' for the first time — this may take a minute...")
            }
            print("[TranscriptionEngine] Loading model '\(model)'...")
            whisper = try await WhisperKit(model: model, downloadBase: modelDir)
            print("[TranscriptionEngine] Ready.")
        } catch {
            print("[TranscriptionEngine] Failed to load model '\(model)': \(error)")
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

    func transcribe(buffer: [Float], language: String? = nil) async throws -> String {
        guard let whisper else {
            throw TranscriptionError.modelNotLoaded
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            skipSpecialTokens: true
        )

        let results = try await whisper.transcribe(audioArray: buffer, decodeOptions: options)
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    // MARK: - Available models

    static let availableModels = ["tiny", "base", "small", "medium", "large-v3"]
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not yet loaded. Please wait a moment."
        }
    }
}
