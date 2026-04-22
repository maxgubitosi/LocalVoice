import Foundation

struct LLMPrompt: Codable, Identifiable {
    let id: UUID
    var name: String
    var instruction: String
    let isPreset: Bool
    var keyNumber: Int?
}

extension LLMPrompt {
    static let presetImprove = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Improve",
        instruction: "Polish everything — fix grammar, punctuation, remove filler words (um, uh, like, you know, right), clean run-on sentences, improve flow. Preserve the speaker's exact intent and vocabulary. Return ONLY the rewritten text, no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 1
    )

    static let presetCorrect = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Correct",
        instruction: "Fix ONLY words clearly misrecognized by speech recognition (wrong homophones, garbled words, obvious substitution errors). Do NOT rephrase, restructure, or improve the text in any way. Preserve every word that could plausibly be what the speaker said. Return ONLY the corrected text, no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 2
    )

    static let presetPromptify = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Promptify",
        instruction: "Convert the raw dictation into a clear, well-structured prompt for an LLM. Infer the user's intent. Reformulate as a precise instruction: define the task, provide relevant context, specify desired output format, and include constraints if needed. Return ONLY the reformulated prompt, no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 3
    )

    static let presetFormalize = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Formalize",
        instruction: "Rewrite in a professional, formal register suitable for business emails or official documents. Preserve all content and factual details exactly. Eliminate casual language, contractions, and colloquialisms. Return ONLY the rewritten text, no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 4
    )

    static let allPresets: [LLMPrompt] = [presetImprove, presetCorrect, presetPromptify, presetFormalize]
}
