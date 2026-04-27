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
        XCTAssertTrue(result.contains("The user is dictating into \"Notes\""))
        XCTAssertTrue(result.contains("Language:"))
        XCTAssertTrue(result.contains("Do not translate"))
        XCTAssertTrue(result.contains("User said:\n\"\"\"\n\(transcript)\n\"\"\""))
    }

    func testNoThinkIsOnlyAddedForSupportedModels() {
        let qwenPrompt = PromptComposer.compose(
            transcript: "clean this up",
            prompt: LLMPrompt.presetImprove,
            appContext: nil,
            detectedLanguage: "en",
            modelID: "mlx-community/Qwen3-1.7B-4bit"
        )

        let gemmaPrompt = PromptComposer.compose(
            transcript: "clean this up",
            prompt: LLMPrompt.presetImprove,
            appContext: nil,
            detectedLanguage: "en",
            modelID: "mlx-community/gemma-3-1b-it-qat-4bit"
        )

        XCTAssertTrue(qwenPrompt.contains("/no_think"))
        XCTAssertFalse(gemmaPrompt.contains("/no_think"))
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
        XCTAssertEqual(PromptComposer.maxTokens(for: "short note"), 256)

        let longTranscript = Array(repeating: "word", count: 1_000).joined(separator: " ")
        XCTAssertEqual(PromptComposer.maxTokens(for: longTranscript), 2048)
    }
}
