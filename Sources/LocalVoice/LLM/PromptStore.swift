import Foundation

final class PromptStore {
    private(set) var prompts: [LLMPrompt]
    private let fileURL: URL

    init() {
        fileURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalVoice/prompts.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([LLMPrompt].self, from: data) {
            prompts = decoded
        } else {
            prompts = LLMPrompt.allPresets
            save()
        }
    }

    func prompt(withKeyNumber n: Int) -> LLMPrompt? {
        prompts.first { $0.keyNumber == n }
    }

    func activePrompt(id: UUID?) -> LLMPrompt {
        prompts.first { $0.id == id } ?? LLMPrompt.presetMejorar
    }

    func add(_ prompt: LLMPrompt) {
        prompts.append(prompt)
        save()
    }

    func update(_ prompt: LLMPrompt) {
        guard !prompt.isPreset,
              let index = prompts.firstIndex(where: { $0.id == prompt.id }) else { return }
        prompts[index] = prompt
        save()
    }

    func delete(_ prompt: LLMPrompt) {
        prompts.removeAll { $0.id == prompt.id && !$0.isPreset }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(prompts) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }
}
