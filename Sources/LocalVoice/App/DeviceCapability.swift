import Foundation

enum DeviceCapability {

    static var recommendedMLXModel: String {
        let ram = physicalMemoryGB
        switch ram {
        case 24...: return "mlx-community/Qwen3-8B-4bit"
        case 16...: return "mlx-community/Qwen3-4B-4bit"
        default:    return "mlx-community/Qwen3-1.7B-4bit"
        }
    }

    static var recommendedMLXModelLabel: String {
        let ram = physicalMemoryGB
        switch ram {
        case 24...: return "Higher quality — recommended for your Mac"
        case 16...: return "Balanced — recommended for your Mac"
        default:    return "Fast — recommended for your Mac"
        }
    }

    static var chipGeneration: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brand = String(cString: buffer)

        if brand.contains("Apple") {
            for gen in ["M4", "M3", "M2", "M1"] {
                if brand.contains(gen) { return "Apple \(gen)" }
            }
            return "Apple Silicon"
        }
        return brand
    }

    static var chipGenerationNumber: Int {
        let gen = chipGeneration
        if gen.contains("M4") { return 4 }
        if gen.contains("M3") { return 3 }
        if gen.contains("M2") { return 2 }
        if gen.contains("M1") { return 1 }
        return 0
    }

    static var physicalMemoryGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }
}
