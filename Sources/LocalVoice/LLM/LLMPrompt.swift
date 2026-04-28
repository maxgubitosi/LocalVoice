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
        name: "Clean",
        instruction: "Clean up dictated text for immediate insertion. Fix punctuation, casing, obvious grammar issues, repeated words, filler words, and likely ASR mistakes when a near-sounding correction is clearly more plausible. Restore opening question/exclamation marks in Spanish when needed. Preserve intent, voice, facts, names, numbers, URLs, code, and commands. Return only the final text, with no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 1
    )

    static let presetCorrect = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Correct ASR",
        instruction: "Recover what the speaker most likely said by correcting clear speech-recognition mistakes: wrong homophones, near-homophones, garbled words, wrong word boundaries, missing punctuation, accents, and obvious substitutions. Use surrounding context and app context to choose the semantically plausible phrase. Do not summarize, embellish, or improve style beyond ASR correction. Preserve every word that could plausibly be what the speaker said. Return only the corrected text, with no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 2
    )

    static let presetPromptify = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Promptify",
        instruction: "Convert the dictation into a clear, actionable prompt for an LLM. Infer the user's intended task, organize relevant context, include constraints, and specify the desired output format when useful. Do not add facts the user did not provide. Return only the reformulated prompt, with no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 3
    )

    static let presetFormalize = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Formal",
        instruction: "Rewrite in a professional, polished register suitable for business email, documentation, or official communication. Preserve all facts, decisions, names, numbers, and requested actions. Remove casual phrasing only when it improves professionalism. Return only the final text, with no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 4
    )

    static let presetMessage = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Message",
        instruction: "Rewrite the dictation as a concise, natural message for chat or email. Keep it human, direct, and appropriately warm for the active app. Preserve the user's intent and all concrete details. Return only the final message, with no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 5
    )

    static let presetNotes = LLMPrompt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        name: "Notes",
        instruction: "Turn the dictation into organized notes. Use short headings or bullets only when they help readability. Capture tasks, decisions, names, dates, and follow-ups without inventing missing details. Return only the final notes, with no explanations or quotation marks.",
        isPreset: true,
        keyNumber: 6
    )

    static let allPresets: [LLMPrompt] = [
        presetImprove,
        presetCorrect,
        presetPromptify,
        presetFormalize,
        presetMessage,
        presetNotes
    ]
}
