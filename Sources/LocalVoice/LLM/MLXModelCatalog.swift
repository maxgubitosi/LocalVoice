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
            id: "mlx-community/gemma-4-e2b-it-4bit",
            displayName: "Gemma 4 E2B Instruct (4-bit)",
            family: "Gemma",
            estimatedRAMGB: 4.5,
            downloadSizeGB: 3.6,
            qualityLabel: "SOTA fast",
            license: "Apache 2.0",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/Qwen3.5-2B-OptiQ-4bit",
            displayName: "Qwen3.5 2B OptiQ (4-bit)",
            family: "Qwen",
            estimatedRAMGB: 2.0,
            downloadSizeGB: 1.4,
            qualityLabel: "Tiny SOTA",
            license: "Apache 2.0",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/Qwen3.5-2B-OptiQ-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/Phi-4-mini-instruct-4bit",
            displayName: "Phi-4 Mini Instruct (4-bit)",
            family: "Phi",
            estimatedRAMGB: 3.0,
            downloadSizeGB: 2.2,
            qualityLabel: "Fast reasoning",
            license: "MIT",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/Phi-4-mini-instruct-4bit",
            isExperimental: false
        ),
        MLXModelInfo(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B Instruct (4-bit)",
            family: "Gemma",
            estimatedRAMGB: 6.5,
            downloadSizeGB: 5.2,
            qualityLabel: "SOTA quality",
            license: "Apache 2.0",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit",
            isExperimental: false
        ),
    ]

    static let experimentalCandidates: [MLXModelInfo] = [
        MLXModelInfo(
            id: "mlx-community/Qwen3.5-4B-4bit",
            displayName: "Qwen3.5 4B (4-bit)",
            family: "Qwen",
            estimatedRAMGB: 3.5,
            downloadSizeGB: 3.0,
            qualityLabel: "Experimental",
            license: "Apache 2.0",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/Qwen3.5-4B-4bit",
            isExperimental: true
        ),
        MLXModelInfo(
            id: "mlx-community/Qwen3-4B-4bit",
            displayName: "Qwen3 4B (4-bit)",
            family: "Qwen",
            estimatedRAMGB: 3.0,
            downloadSizeGB: 2.3,
            qualityLabel: "Experimental",
            license: "Apache 2.0",
            supportsNoThink: true,
            sourceURL: "https://huggingface.co/mlx-community/Qwen3-4B-4bit",
            isExperimental: true
        ),
        MLXModelInfo(
            id: "mlx-community/gemma-3-1b-it-qat-4bit",
            displayName: "Gemma 3 1B QAT (4-bit)",
            family: "Gemma",
            estimatedRAMGB: 1.3,
            downloadSizeGB: 0.7,
            qualityLabel: "Legacy fallback",
            license: "Gemma",
            supportsNoThink: false,
            sourceURL: "https://huggingface.co/mlx-community/gemma-3-1b-it-qat-4bit",
            isExperimental: true
        ),
    ]

    static var smokeTestCandidates: [MLXModelInfo] {
        models + experimentalCandidates
    }

    static var recommendedModelID: String { DeviceCapability.recommendedMLXModel }

    static func model(id: String) -> MLXModelInfo? {
        models.first { $0.id == id }
    }

    static func supportsNoThink(_ modelID: String) -> Bool {
        smokeTestCandidates.first { $0.id == modelID }?.supportsNoThink ?? false
    }
}
