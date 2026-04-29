import XCTest
@testable import LocalVoice

final class PromptComposerTests: XCTestCase {
    func testComposeIncludesStructuredContextAndLiteralDictation() {
        let transcript = "mandale a Ana que llego a las 5 y que revise https://example.com"

        let result = PromptComposer.compose(
            transcript: transcript,
            prompt: LLMPrompt.presetImprove,
            appContext: "Notes",
            detectedLanguage: "es",
            modelID: "mlx-community/Qwen3-4B-4bit"
        )

        XCTAssertTrue(result.contains("Task:"))
        XCTAssertTrue(result.contains(LLMPrompt.presetImprove.instruction))
        XCTAssertTrue(result.contains("App context:"))
        XCTAssertTrue(result.contains("Dictating into \"Notes\""))
        XCTAssertTrue(result.contains("Language:"))
        XCTAssertTrue(result.contains("Respond in Spanish."))
        XCTAssertFalse(result.contains("Dictation language appears"))
        XCTAssertFalse(result.contains("same language as the user's dictation"))
        XCTAssertTrue(result.contains("without quotation marks"))
        XCTAssertTrue(result.contains("near-sounding correction"))
        XCTAssertFalse(result.contains("cómo están dando"))
        XCTAssertTrue(result.contains("User said:\n\"\"\"\n\(transcript)\n\"\"\""))
    }

    func testLanguageIsSelectedFromCode() {
        let result = PromptComposer.compose(
            transcript: "hello world",
            prompt: LLMPrompt.presetCorrect,
            appContext: nil,
            detectedLanguage: "en",
            modelID: "mlx-community/Qwen3.5-2B-OptiQ-4bit"
        )

        XCTAssertTrue(result.contains("Respond in English."))
    }

    func testMissingLanguageFallsBackToTranscriptionLanguage() {
        let result = PromptComposer.compose(
            transcript: "hola mundo",
            prompt: LLMPrompt.presetCorrect,
            appContext: nil,
            detectedLanguage: nil,
            modelID: "mlx-community/Qwen3.5-2B-OptiQ-4bit"
        )

        XCTAssertTrue(result.contains("Respond in the transcription language."))
    }

    func testNoThinkIsNotAddedForCurrentVisibleModels() {
        for model in MLXModelCatalog.models {
            let composed = PromptComposer.compose(
                transcript: "clean this up",
                prompt: LLMPrompt.presetImprove,
                appContext: nil,
                detectedLanguage: "en",
                modelID: model.id
            )

            XCTAssertFalse(composed.contains("/no_think"), "\(model.id) should not get /no_think")
        }
    }

    func testNoThinkIsOnlyAddedForSupportedExperimentalModels() {
        let qwenPrompt = PromptComposer.compose(
            transcript: "clean this up",
            prompt: LLMPrompt.presetImprove,
            appContext: nil,
            detectedLanguage: "en",
            modelID: "mlx-community/Qwen3-4B-4bit"
        )

        XCTAssertTrue(qwenPrompt.contains("/no_think"))
    }

    func testPresetInstructionsReturnOnlyFinalText() {
        for prompt in LLMPrompt.allPresets {
            XCTAssertTrue(
                prompt.instruction.localizedCaseInsensitiveContains("return only"),
                "\(prompt.name) should forbid explanations or wrappers"
            )
        }
    }

    func testDynamicTokenLimitStaysWithinBounds() {
        XCTAssertEqual(PromptComposer.maxTokens(for: ""), 0)
        XCTAssertEqual(PromptComposer.maxTokens(for: "   \n\t"), 0)
        XCTAssertEqual(PromptComposer.maxTokens(for: "short note"), 256)

        let longTranscript = Array(repeating: "word", count: 1_000).joined(separator: " ")
        XCTAssertEqual(PromptComposer.maxTokens(for: longTranscript), 3160)

        let fiveMinuteTranscript = Array(repeating: "word", count: 650).joined(separator: " ")
        XCTAssertEqual(PromptComposer.maxTokens(for: fiveMinuteTranscript), 2110)

        let veryLongTranscript = Array(repeating: "word", count: 2_000).joined(separator: " ")
        XCTAssertEqual(PromptComposer.maxTokens(for: veryLongTranscript), 4096)
    }
}
