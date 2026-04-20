import Foundation

/// Detects Apple Silicon generation and RAM to recommend the right Ollama model.
enum DeviceCapability {

    /// Recommended gemma4 variant for this device.
    /// - e2b: lighter, faster — for M1/M2 or <16GB RAM
    /// - e4b: more capable — for M3/M4 or ≥16GB RAM
    static var recommendedGemmaModel: String {
        if shouldUseHeavierModel { return "gemma4:e4b" }
        return "gemma4:e2b"
    }

    static var recommendedGemmaModelReason: String {
        let chip = chipGeneration
        let ram = physicalMemoryGB
        if shouldUseHeavierModel {
            return "gemma4:e4b — recomendado para tu \(chip) con \(ram)GB RAM"
        }
        return "gemma4:e2b — recomendado para tu \(chip) con \(ram)GB RAM (más rápido, menor consumo)"
    }

    // MARK: - Private

    private static var shouldUseHeavierModel: Bool {
        // M3/M4 chips or ≥16GB RAM can comfortably run 4b
        let gen = chipGenerationNumber
        let ram = physicalMemoryGB
        return gen >= 3 || ram >= 16
    }

    static var chipGeneration: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let brand = String(cString: buffer)

        // Apple Silicon shows as "Apple M1", "Apple M2", etc.
        if brand.contains("Apple") {
            for gen in ["M4", "M3", "M2", "M1"] {
                if brand.contains(gen) { return "Apple \(gen)" }
            }
            return "Apple Silicon"
        }
        return brand
    }

    private static var chipGenerationNumber: Int {
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
