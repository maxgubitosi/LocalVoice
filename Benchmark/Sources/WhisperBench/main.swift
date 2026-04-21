import WhisperKit
import Foundation

// MARK: - Argument parsing

func parseArgs() -> (audioPath: String, models: [String], language: String?) {
    var audioPath: String? = nil
    var models: [String] = ["base", "small", "medium", "openai_whisper-large-v3_turbo"]
    var language: String? = nil

    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = args.next() {
        switch arg {
        case "--models":
            if let val = args.next() {
                models = val.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            }
        case "--language":
            if let val = args.next(), val != "auto" {
                language = val
            }
        case "--help", "-h":
            print("Usage: WhisperBench <audio_file> [--models base,small,...] [--language es|en|auto]")
            exit(0)
        default:
            if !arg.hasPrefix("-") { audioPath = arg }
        }
    }

    guard let path = audioPath else {
        fputs("Error: se requiere un archivo de audio como primer argumento.\n", stderr)
        fputs("Uso: WhisperBench <audio_file> [--models base,small,...] [--language es|en|auto]\n", stderr)
        exit(1)
    }
    guard FileManager.default.fileExists(atPath: path) else {
        fputs("Error: no se encontró el archivo '\(path)'\n", stderr)
        exit(1)
    }
    return (path, models, language)
}

// MARK: - Model directory (shared with the main app)

func sharedModelDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = base.appendingPathComponent("LocalVoice/Models", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// MARK: - Output types

struct ModelResult: Encodable {
    let model: String
    let load_ms: Int
    let transcribe_ms: Int
    let text: String
    var error: String?
}

struct BenchmarkOutput: Encodable {
    let audio_file: String
    let audio_duration_seconds: Double
    let timestamp: String
    let models_tested: [String]
    let language: String
    let results: [ModelResult]
}

// MARK: - Benchmark

func runBenchmark(audioPath: String, models: [String], language: String?) async {
    fputs("[WhisperBench] Cargando audio desde '\(audioPath)'...\n", stderr)

    let audioArray: [Float]
    do {
        audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioPath)
    } catch {
        fputs("Error al cargar audio: \(error)\n", stderr)
        exit(1)
    }

    let audioDuration = Double(audioArray.count) / Double(WhisperKit.sampleRate)
    fputs("[WhisperBench] Audio cargado: \(String(format: "%.1f", audioDuration))s (\(audioArray.count) samples)\n", stderr)

    let modelDir = sharedModelDirectory()
    var results: [ModelResult] = []

    let decodeOptions = DecodingOptions(
        task: .transcribe,
        language: language,
        temperature: 0,
        usePrefillPrompt: true,
        detectLanguage: language == nil,
        skipSpecialTokens: true
    )

    for model in models {
        fputs("[WhisperBench] ── Modelo: \(model)\n", stderr)

        let loadStart = Date()
        let whisper: WhisperKit
        do {
            whisper = try await WhisperKit(model: model, downloadBase: modelDir, verbose: false, logLevel: .none)
        } catch {
            fputs("  Error cargando '\(model)': \(error)\n", stderr)
            results.append(ModelResult(model: model, load_ms: 0, transcribe_ms: 0, text: "", error: error.localizedDescription))
            continue
        }
        let loadMs = Int(Date().timeIntervalSince(loadStart) * 1000)
        fputs("  Carga: \(loadMs)ms\n", stderr)

        let transcribeStart = Date()
        let transcriptionResults: [TranscriptionResult]
        do {
            transcriptionResults = try await whisper.transcribe(audioArray: audioArray, decodeOptions: decodeOptions)
        } catch {
            fputs("  Error transcribiendo con '\(model)': \(error)\n", stderr)
            results.append(ModelResult(model: model, load_ms: loadMs, transcribe_ms: 0, text: "", error: error.localizedDescription))
            continue
        }
        let transcribeMs = Int(Date().timeIntervalSince(transcribeStart) * 1000)

        let text = transcriptionResults.map { $0.text }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        fputs("  Transcripción: \(transcribeMs)ms\n", stderr)
        fputs("  Texto: \"\(text.prefix(80))\(text.count > 80 ? "..." : "")\"\n", stderr)

        results.append(ModelResult(model: model, load_ms: loadMs, transcribe_ms: transcribeMs, text: text))
    }

    let iso = ISO8601DateFormatter()
    let output = BenchmarkOutput(
        audio_file: URL(fileURLWithPath: audioPath).lastPathComponent,
        audio_duration_seconds: (audioDuration * 10).rounded() / 10,
        timestamp: iso.string(from: Date()),
        models_tested: models,
        language: language ?? "auto",
        results: results
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let json = try! encoder.encode(output)
    print(String(data: json, encoding: .utf8)!)
}

// MARK: - Entry point

let (audioPath, models, language) = parseArgs()
await runBenchmark(audioPath: audioPath, models: models, language: language)
