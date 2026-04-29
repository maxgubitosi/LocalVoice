import XCTest
@testable import LocalVoice

final class TranscriptionRecordTests: XCTestCase {
    func testFinalTextPrefersRefinedTextWhenAvailable() {
        let record = TranscriptionRecord(
            timestamp: Date(),
            audioDurationSeconds: 1,
            wordCount: 4,
            detectedLanguage: "es",
            frontmostAppBundleID: nil,
            frontmostAppName: nil,
            mode: AppMode.llmRewrite.rawValue,
            whisperModel: "large-v3-turbo",
            llmModel: "mlx-community/gemma-4-e2b-it-4bit",
            llmLatencySeconds: 1,
            transcribedText: "A ver esto cómo están dando.",
            originalText: "A ver esto cómo están dando.",
            refinedText: "A ver, ¿cómo está andando esto?",
            transcriptionLatencySeconds: 1,
            processingLatencySeconds: 2,
            promptName: "Correct ASR"
        )

        XCTAssertEqual(record.finalText, "A ver, ¿cómo está andando esto?")
    }

    func testFinalTextFallsBackToTranscriptionForDirectMode() {
        let record = TranscriptionRecord(
            timestamp: Date(),
            audioDurationSeconds: 1,
            wordCount: 4,
            detectedLanguage: "es",
            frontmostAppBundleID: nil,
            frontmostAppName: nil,
            mode: AppMode.directTranscription.rawValue,
            whisperModel: "large-v3-turbo",
            llmModel: nil,
            llmLatencySeconds: nil,
            transcribedText: "Texto directo.",
            originalText: nil,
            refinedText: nil,
            transcriptionLatencySeconds: 1,
            processingLatencySeconds: 1,
            promptName: nil
        )

        XCTAssertEqual(record.finalText, "Texto directo.")
    }

    func testStoresBrowserPageContext() {
        let record = TranscriptionRecord(
            timestamp: Date(),
            audioDurationSeconds: 1,
            wordCount: 4,
            detectedLanguage: "es",
            frontmostAppBundleID: "com.google.Chrome",
            frontmostAppName: "Google Chrome",
            frontmostPageTitle: "LocalVoice Pull Request",
            frontmostPageURL: "https://github.com/example/localvoice/pull/12",
            mode: AppMode.llmRewrite.rawValue,
            whisperModel: "large-v3-turbo",
            llmModel: "mlx-community/Qwen3.5-2B-OptiQ-4bit",
            llmLatencySeconds: 1,
            transcribedText: "Revisar esto.",
            originalText: "Revisar esto.",
            refinedText: "Revisar esto.",
            transcriptionLatencySeconds: 1,
            processingLatencySeconds: 2,
            promptName: "Improve"
        )

        XCTAssertEqual(record.frontmostPageTitle, "LocalVoice Pull Request")
        XCTAssertEqual(record.frontmostPageURL, "https://github.com/example/localvoice/pull/12")
    }
}
