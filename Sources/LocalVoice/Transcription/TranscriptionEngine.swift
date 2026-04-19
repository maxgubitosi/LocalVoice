import WhisperKit
import Foundation

final class TranscriptionEngine {
    private var whisper: WhisperKit?
    private var currentModel: String = "base"
    private let modelLoadLock = NSLock()

    func loadModel(named model: String = "base") async {
        modelLoadLock.lock()
        defer { modelLoadLock.unlock() }

        currentModel = model
        do {
            whisper = try await WhisperKit(model: model)
            print("[TranscriptionEngine] Loaded model: \(model)")
        } catch {
            print("[TranscriptionEngine] Failed to load model '\(model)': \(error)")
        }
    }

    func transcribe(buffer: [Float]) async throws -> String {
        guard let whisper else {
            throw TranscriptionError.modelNotLoaded
        }

        let options = DecodingOptions(
            language: nil, // auto-detect
            task: .transcribe,
            temperature: 0,
            usePrefillPrompt: true,
            skipSpecialTokens: true
        )

        let results = try await whisper.transcribe(audioArray: buffer, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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
