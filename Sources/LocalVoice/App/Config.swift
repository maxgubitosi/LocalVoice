import OSLog

// Per-subsystem loggers — one per module, used directly in each file.
// Visible in Console.app: filter by subsystem "com.localvoice.app"
extension Logger {
    private static let subsystem = "com.localvoice.app"

    static let pipeline       = Logger(subsystem: subsystem, category: "Pipeline")
    static let audio          = Logger(subsystem: subsystem, category: "AudioCapture")
    static let hotkey         = Logger(subsystem: subsystem, category: "HotkeyManager")
    static let transcription  = Logger(subsystem: subsystem, category: "Transcription")
    static let llm            = Logger(subsystem: subsystem, category: "MLXClient")
    static let textInserter   = Logger(subsystem: subsystem, category: "TextInserter")
    static let persistence    = Logger(subsystem: subsystem, category: "Persistence")
}
