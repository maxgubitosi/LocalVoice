import Foundation
import OSLog

final class PromptStore: ObservableObject {
    @Published private(set) var prompts: [LLMPrompt]
    private let fileURL: URL

    // Tracks which preset IDs the user has intentionally modified.
    // Presets NOT in this set always load from code (guarantees correct language/content
    // and discards stale content written by older app versions).
    private var modifiedPresetIDs: Set<UUID> {
        get {
            let strings = UserDefaults.standard.stringArray(forKey: "modifiedPresetIDs") ?? []
            return Set(strings.compactMap(UUID.init))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: "modifiedPresetIDs")
        }
    }

    init() {
        fileURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalVoice/prompts.json")

        let saved = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([LLMPrompt].self, from: $0) } ?? []

        let savedByID = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        let presetIDs = Set(LLMPrompt.allPresets.map(\.id))

        // Load UserDefaults before self is fully initialized
        var modifiedIDs: Set<UUID> = {
            let strings = UserDefaults.standard.stringArray(forKey: "modifiedPresetIDs") ?? []
            return Set(strings.compactMap(UUID.init))
        }()
        var migratedLegacyPreset = false

        var result: [LLMPrompt] = LLMPrompt.allPresets.map { preset in
            // Only restore a preset from disk if the user explicitly modified it.
            if modifiedIDs.contains(preset.id), let s = savedByID[preset.id] {
                if Self.isLegacyDefaultPreset(s) {
                    modifiedIDs.remove(preset.id)
                    migratedLegacyPreset = true
                    return preset
                }
                return s
            }
            return preset
        }
        result += saved.filter { !presetIDs.contains($0.id) }

        prompts = result

        if migratedLegacyPreset {
            modifiedPresetIDs = modifiedIDs
            save()
        } else if !FileManager.default.fileExists(atPath: fileURL.path) {
            save()
        }
    }

    func prompt(withKeyNumber n: Int) -> LLMPrompt? {
        prompts.first { $0.keyNumber == n }
    }

    func activePrompt(id: UUID?) -> LLMPrompt {
        prompts.first { $0.id == id } ?? LLMPrompt.presetImprove
    }

    func add(_ prompt: LLMPrompt) {
        prompts.append(prompt)
        save()
    }

    func update(_ prompt: LLMPrompt) {
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        prompts[index] = prompt
        if prompt.isPreset {
            var ids = modifiedPresetIDs
            ids.insert(prompt.id)
            modifiedPresetIDs = ids
        }
        save()
    }

    func delete(_ prompt: LLMPrompt) {
        prompts.removeAll { $0.id == prompt.id && !$0.isPreset }
        save()
    }

    func isModified(_ prompt: LLMPrompt) -> Bool {
        guard prompt.isPreset,
              let original = LLMPrompt.allPresets.first(where: { $0.id == prompt.id })
        else { return false }
        return prompt.name != original.name
            || prompt.instruction != original.instruction
            || prompt.keyNumber != original.keyNumber
    }

    func revertToDefault(_ prompt: LLMPrompt) {
        guard prompt.isPreset,
              let original = LLMPrompt.allPresets.first(where: { $0.id == prompt.id }),
              let index = prompts.firstIndex(where: { $0.id == prompt.id })
        else { return }
        prompts[index] = original
        var ids = modifiedPresetIDs
        ids.remove(prompt.id)
        modifiedPresetIDs = ids
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(prompts)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.persistence.error("Failed to save prompts to disk: \(error)")
        }
    }

    private static func isLegacyDefaultPreset(_ prompt: LLMPrompt) -> Bool {
        legacyDefaults.contains { legacy in
            legacy.id == prompt.id
                && legacy.name == prompt.name
                && legacy.instruction == prompt.instruction
                && legacy.keyNumber == prompt.keyNumber
        }
    }

    private static let legacyDefaults: [LLMPrompt] = [
        LLMPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Improve",
            instruction: "Polish everything — fix grammar, punctuation, remove filler words (um, uh, like, you know, right), clean run-on sentences, improve flow. Preserve the speaker's exact intent and vocabulary. Return ONLY the rewritten text, no explanations or quotation marks.",
            isPreset: true,
            keyNumber: 1
        ),
        LLMPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Correct",
            instruction: "Fix ONLY words clearly misrecognized by speech recognition (wrong homophones, garbled words, obvious substitution errors). Do NOT rephrase, restructure, or improve the text in any way. Preserve every word that could plausibly be what the speaker said. Return ONLY the corrected text, no explanations or quotation marks.",
            isPreset: true,
            keyNumber: 2
        ),
        LLMPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Promptify",
            instruction: "Convert the raw dictation into a clear, well-structured prompt for an LLM. Infer the user's intent. Reformulate as a precise instruction: define the task, provide relevant context, specify desired output format, and include constraints if needed. Return ONLY the reformulated prompt, no explanations or quotation marks.",
            isPreset: true,
            keyNumber: 3
        ),
        LLMPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Formalize",
            instruction: "Rewrite in a professional, formal register suitable for business emails or official documents. Preserve all content and factual details exactly. Eliminate casual language, contractions, and colloquialisms. Return ONLY the rewritten text, no explanations or quotation marks.",
            isPreset: true,
            keyNumber: 4
        ),
        LLMPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Clean",
            instruction: "Clean up dictated text for immediate insertion. Fix punctuation, casing, obvious grammar issues, repeated words, and filler words. Keep the speaker's intent, voice, vocabulary, facts, names, numbers, URLs, code, and commands intact. Return only the final text, with no explanations or quotation marks.",
            isPreset: true,
            keyNumber: 1
        ),
        LLMPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Correct ASR",
            instruction: "Correct only clear speech recognition mistakes such as wrong homophones, garbled words, missing punctuation, or obvious substitutions. Do not rewrite, summarize, embellish, or improve style. Preserve every word that could plausibly be what the speaker said. Return only the corrected text, with no explanations or quotation marks.",
            isPreset: true,
            keyNumber: 2
        ),
        LLMPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Clean",
            instruction: "Clean up dictated text for immediate insertion. Fix punctuation, casing, obvious grammar issues, repeated words, filler words, and likely ASR mistakes when the transcript is semantically odd but a near-sounding correction is clearly more plausible. Restore Spanish opening question/exclamation marks when needed. Keep the speaker's intent, voice, vocabulary, facts, names, numbers, URLs, code, and commands intact. Return only the final text, with no explanations or quotation marks.",
            isPreset: true,
            keyNumber: 1
        ),
        LLMPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Correct ASR",
            instruction: "Recover what the speaker most likely said by correcting clear speech-recognition mistakes: wrong homophones, near-homophones, garbled words, wrong word boundaries, missing punctuation, and obvious substitutions. Use surrounding context and app context to choose the semantically plausible phrase. For example, in Spanish app/model context, \"cómo están dando\" is likely \"cómo están andando\" or \"cómo está andando\". Do not summarize, embellish, or improve style beyond ASR correction. Preserve every word that could plausibly be what the speaker said. Return only the corrected text, with no explanations or quotation marks.",
            isPreset: true,
            keyNumber: 2
        )
    ]
}
