import Hub
import MLXLMCommon
import Foundation
import OSLog

@MainActor
final class MLXModelManager: ObservableObject {
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var downloadedModels: Set<String> = []

    init() {
        refreshDownloadedModels()
    }

    func refreshDownloadedModels() {
        downloadedModels = Set(MLXModelCatalog.models.map(\.id).filter { isDownloaded($0) })
    }

    func isDownloaded(_ modelID: String) -> Bool {
        let dir = Self.localPath(for: modelID)
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.contains { $0.hasSuffix(".safetensors") }
    }

    func downloadModel(_ modelID: String) async throws {
        guard downloadProgress[modelID] == nil else { return }
        downloadProgress[modelID] = 0

        let hub = HubApi(downloadBase: MLXClient.modelsDirectory)
        do {
            try await hub.snapshot(
                from: modelID,
                matching: ["*.safetensors", "*.json", "*.jinja"],
                progressHandler: { [weak self] progress in
                    let fraction = progress.totalUnitCount > 0
                        ? Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                        : 0
                    Task { @MainActor [weak self] in
                        self?.downloadProgress[modelID] = fraction
                    }
                }
            )
            downloadProgress.removeValue(forKey: modelID)
            downloadedModels.insert(modelID)
            Logger.llm.info("Downloaded MLX model: \(modelID)")
        } catch {
            downloadProgress.removeValue(forKey: modelID)
            Logger.llm.error("Failed to download \(modelID): \(error)")
            throw error
        }
    }

    func deleteModel(_ modelID: String) throws {
        let dir = Self.localPath(for: modelID)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try FileManager.default.removeItem(at: dir)
        downloadedModels.remove(modelID)
        Logger.llm.info("Deleted MLX model: \(modelID)")
    }

    // Mirrors HubApi.localRepoLocation: downloadBase/models/{org}/{model}
    static func localPath(for modelID: String) -> URL {
        MLXClient.modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent(modelID)
    }
}
