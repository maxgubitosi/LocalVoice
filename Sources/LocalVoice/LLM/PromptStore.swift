import Foundation
import OSLog

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
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                save()
            }
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
        guard let index = prompts.firstIndex(where: { $0.id == prompt.id }),
              !prompts[index].isPreset else { return }
        prompts[index] = prompt
        save()
    }

    func delete(_ prompt: LLMPrompt) {
        prompts.removeAll { $0.id == prompt.id && !$0.isPreset }
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
