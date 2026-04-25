import Foundation

struct MLXModelInfo: Identifiable {
    let id: String
    let displayName: String
    let paramCount: String
    let estimatedRAMGB: Double
    let downloadSizeGB: Double
    let speedLabel: String
}

enum MLXModelCatalog {
    static let models: [MLXModelInfo] = [
        MLXModelInfo(
            id: "mlx-community/Qwen3.5-2B-MLX-4bit",
            displayName: "Qwen 3.5 2B (4-bit)",
            paramCount: "2B",
            estimatedRAMGB: 1.5,
            downloadSizeGB: 1.6,
            speedLabel: "Fast"
        ),
        MLXModelInfo(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit",
            displayName: "Qwen 3.5 4B (4-bit)",
            paramCount: "4B",
            estimatedRAMGB: 3.0,
            downloadSizeGB: 2.9,
            speedLabel: "Balanced"
        ),
        MLXModelInfo(
            id: "mlx-community/Qwen3.5-9B-MLX-4bit",
            displayName: "Qwen 3.5 9B (4-bit)",
            paramCount: "9B",
            estimatedRAMGB: 5.5,
            downloadSizeGB: 5.0,
            speedLabel: "High quality"
        ),
        MLXModelInfo(
            id: "mlx-community/Qwen3.5-27B-4bit",
            displayName: "Qwen 3.5 27B (4-bit)",
            paramCount: "27B",
            estimatedRAMGB: 16.0,
            downloadSizeGB: 14.0,
            speedLabel: "Best quality"
        ),
    ]

    static var recommendedModelID: String { DeviceCapability.recommendedMLXModel }
}
