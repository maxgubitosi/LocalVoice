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
        let modifiedIDs: Set<UUID> = {
            let strings = UserDefaults.standard.stringArray(forKey: "modifiedPresetIDs") ?? []
            return Set(strings.compactMap(UUID.init))
        }()

        var result: [LLMPrompt] = LLMPrompt.allPresets.map { preset in
            // Only restore a preset from disk if the user explicitly modified it.
            if modifiedIDs.contains(preset.id), let s = savedByID[preset.id] { return s }
            return preset
        }
        result += saved.filter { !presetIDs.contains($0.id) }

        prompts = result

        if !FileManager.default.fileExists(atPath: fileURL.path) { save() }
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
}
