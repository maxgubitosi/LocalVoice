import Foundation

struct MLXModelInfo: Identifiable {
    let id: String
    let displayName: String
    let family: String
    let estimatedRAMGB: Double
    let downloadSizeGB: Double
    let qualityLabel: String
    let license: String
    let supportsNoThink: Bool
    let sourceURL: String
    let isExperimental: Bool
}

enum MLXModelCatalog {
    static let models: [MLXModelInfo] = [
        MLXModelInfo(
            id: "mlx-community/Qwen3-1.7B-4bit",
            displayName: "Qwen3 1.7B (4-bit)",
            family: "Qwen",
            estimatedRAMGB: 1.5,
            downloadSizeGB: 1.0,
            qualityLabel: "Fast",
            license: "Apache 2.0",
            supportsNoThink: true,
            sourceURL: "https://huggingface.co/mlx-community/Qwen3-1.7B-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/Qwen3-4B-4bit",
            displayName: "Qwen3 4B (4-bit)",
            family: "Qwen",
            estimatedRAMGB: 3.0,
            downloadSizeGB: 2.3,
            qualityLabel: "Balanced",
            license: "Apache 2.0",
            supportsNoThink: true,
            sourceURL: "https://huggingface.co/mlx-community/Qwen3-4B-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/Qwen3-8B-4bit",
            displayName: "Qwen3 8B (4-bit)",
            family: "Qwen",
            estimatedRAMGB: 5.5,
            downloadSizeGB: 4.6,
            qualityLabel: "Higher quality",
            license: "Apache 2.0",
            supportsNoThink: true,
            sourceURL: "https://huggingface.co/mlx-community/Qwen3-8B-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/gemma-3-1b-it-qat-4bit",
            displayName: "Gemma 3 1B QAT (4-bit)",
            family: "Gemma",
            estimatedRAMGB: 1.3,
            downloadSizeGB: 0.7,
            qualityLabel: "Fast",
            license: "Gemma",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/gemma-3n-E2B-it-lm-4bit",
            displayName: "Gemma 3n E2B Text (4-bit)",
            family: "Gemma",
            estimatedRAMGB: 3.2,
            downloadSizeGB: 2.5,
            qualityLabel: "Balanced",
            license: "Gemma",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/gemma-3n-E2B-it-lm-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B Instruct (4-bit)",
            family: "Llama",
            estimatedRAMGB: 2.5,
            downloadSizeGB: 1.8,
            qualityLabel: "Balanced",
            license: "Llama 3.2",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            displayName: "Phi 3.5 Mini Instruct (4-bit)",
            family: "Phi",
            estimatedRAMGB: 3.0,
            downloadSizeGB: 2.2,
            qualityLabel: "Balanced",
            license: "MIT",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit",
            isExperimental: false
        ),
    ]

    static var recommendedModelID: String { DeviceCapability.recommendedMLXModel }

    static func model(id: String) -> MLXModelInfo? {
        models.first { $0.id == id }
    }

    static func supportsNoThink(_ modelID: String) -> Bool {
        model(id: modelID)?.supportsNoThink ?? false
    }
}
