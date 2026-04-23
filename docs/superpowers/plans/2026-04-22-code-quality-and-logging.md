# Code Quality & Logging Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix six concrete issues: upgrade the logging system to `os.Logger`, eliminate a race condition in audio capture, connect the hotkey key code setting to HotkeyManager, fix a hard-crash on SwiftData init, cancel in-flight transcription tasks on new recording, and stop PromptStore from silently dropping save errors.

**Architecture:** Changes are isolated to individual modules — no cross-cutting rewrites. The logging migration touches all files but each change is mechanical (swap `debugLog(...)` for `logger.debug(...)`). Everything else is a targeted fix in a single file.

**Tech Stack:** Swift 5.10, macOS 14+, AVFoundation, SwiftData, CoreGraphics event tap, `os.Logger` (Unified Logging), structured concurrency (`Task`, `Task.cancel()`).

---

## Files Modified

| File | Change |
|---|---|
| `Sources/LocalVoice/App/Config.swift` | Replace `debugLog` global with `os.Logger`-backed module loggers |
| `Sources/LocalVoice/Audio/AudioCapture.swift` | Add serial `DispatchQueue` to synchronize `samples` access; add `logger` |
| `Sources/LocalVoice/Audio/HotkeyManager.swift` | Wire `AppSettings.hotkeyKeyCode` in; fix `state` read off main thread; add `logger` |
| `Sources/LocalVoice/App/AppDelegate.swift` | Replace `try!` with recoverable init; cancel previous `Task` on new recording; add `logger` |
| `Sources/LocalVoice/LLM/PromptStore.swift` | Log save errors instead of swallowing them |
| `Sources/LocalVoice/Transcription/TranscriptionEngine.swift` | Add `logger` (mechanical swap) |
| `Sources/LocalVoice/LLM/OllamaClient.swift` | Add `logger` (mechanical swap) |
| `Sources/LocalVoice/TextInsertion/TextInserter.swift` | Add `logger` (mechanical swap) |

---

## Task 1: Replace `debugLog` with `os.Logger`

**Files:** Modify `Sources/LocalVoice/App/Config.swift`

This removes the `Config.debugLogging` boolean flag and the global `debugLog` function, replacing them with per-subsystem `os.Logger` instances. Each module then uses its own logger directly. The `os.Logger` API requires specifying a `subsystem` (usually the bundle ID) and a `category` (the module name). Messages are visible in Console.app filtered by category and persist across process launches.

- [ ] **Step 1: Replace Config.swift content**

```swift
import OSLog

// Per-subsystem loggers — one per module, used directly in each file.
// Visible in Console.app: filter by subsystem "com.localvoice.app"
extension Logger {
    private static let subsystem = "com.localvoice.app"

    static let pipeline       = Logger(subsystem: subsystem, category: "Pipeline")
    static let audio          = Logger(subsystem: subsystem, category: "AudioCapture")
    static let hotkey         = Logger(subsystem: subsystem, category: "HotkeyManager")
    static let transcription  = Logger(subsystem: subsystem, category: "Transcription")
    static let llm            = Logger(subsystem: subsystem, category: "OllamaClient")
    static let textInserter   = Logger(subsystem: subsystem, category: "TextInserter")
    static let persistence    = Logger(subsystem: subsystem, category: "Persistence")
}
```

- [ ] **Step 2: Build to confirm Config.swift compiles**

```bash
cd /Users/maxi/Downloads/AI\ Projects/LocalVoice
swift build 2>&1 | head -40
```

Expected: errors pointing to every `debugLog(...)` call site — that's correct, we'll fix them in subsequent tasks.

- [ ] **Step 3: Commit Config.swift alone**

```bash
git add Sources/LocalVoice/App/Config.swift
git commit -m "refactor: replace debugLog with os.Logger module loggers"
```

---

## Task 2: Migrate AudioCapture to `os.Logger`

**Files:** Modify `Sources/LocalVoice/Audio/AudioCapture.swift`

Swap every `debugLog(...)` call to `Logger.audio.*`.

- [ ] **Step 1: Replace AudioCapture.swift content**

```swift
import AVFoundation
import OSLog

final class AudioCapture {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var isRecording = false
    private let targetSampleRate: Double = 16000

    func startRecording() {
        guard !isRecording else { return }
        samples = []
        isRecording = true

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat()) else {
            Logger.audio.error("Failed to create audio converter")
            return
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer: buffer, using: converter)
        }

        do {
            try engine.start()
        } catch {
            Logger.audio.error("Engine start error: \(error)")
            input.removeTap(onBus: 0)
            isRecording = false
        }
    }

    func stopRecording(completion: @escaping ([Float]?) -> Void) {
        guard isRecording else { completion(nil); return }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let captured = samples
        completion(captured.isEmpty ? nil : captured)
    }

    // MARK: - Private

    private func convert(buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
        let outputFrameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: whisperFormat(),
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let err = error {
            Logger.audio.error("Conversion error: \(err)")
            return
        }

        guard let channelData = output.floatChannelData else { return }
        let frameCount = Int(output.frameLength)
        samples.append(contentsOf: Array(UnsafeBufferPointer(start: channelData[0], count: frameCount)))
    }

    private func whisperFormat() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "AudioCapture|error:"
```

Expected: no errors from AudioCapture.swift.

- [ ] **Step 3: Commit**

```bash
git add Sources/LocalVoice/Audio/AudioCapture.swift
git commit -m "refactor: migrate AudioCapture logging to os.Logger"
```

---

## Task 3: Fix AudioCapture race condition

**Files:** Modify `Sources/LocalVoice/Audio/AudioCapture.swift`

The AVAudioEngine tap callback runs on a dedicated audio thread. `samples` and `isRecording` are mutated from that thread and read/written from `stopRecording()` which is called from the main thread. This needs a serial `DispatchQueue` acting as a lock: all mutations to `samples` and `isRecording` go through `queue.sync` or happen exclusively on the queue.

The simplest correct fix: use a serial queue for all `samples` access. `startRecording` and `stopRecording` are called from main thread; the tap callback fires from the audio thread. Route all mutations and reads of `samples` through the queue.

- [ ] **Step 1: Add serial queue and fix AudioCapture.swift**

```swift
import AVFoundation
import OSLog

final class AudioCapture {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var isRecording = false
    private let targetSampleRate: Double = 16000
    // Serializes access to `samples` and `isRecording` across the audio thread and main thread.
    private let queue = DispatchQueue(label: "com.localvoice.audiocapture")

    func startRecording() {
        queue.sync {
            guard !isRecording else { return }
            samples = []
            isRecording = true
        }
        // Read isRecording back under queue to decide if we actually started
        let didStart = queue.sync { isRecording }
        guard didStart else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat()) else {
            Logger.audio.error("Failed to create audio converter")
            queue.sync { isRecording = false }
            return
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.convert(buffer: buffer, using: converter)
        }

        do {
            try engine.start()
        } catch {
            Logger.audio.error("Engine start error: \(error)")
            input.removeTap(onBus: 0)
            queue.sync { isRecording = false }
        }
    }

    func stopRecording(completion: @escaping ([Float]?) -> Void) {
        let captured: [Float]? = queue.sync {
            guard isRecording else { return nil }
            isRecording = false
            return samples.isEmpty ? nil : samples
        }
        if captured != nil {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        completion(captured)
    }

    // MARK: - Private

    private func convert(buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) {
        let outputFrameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: whisperFormat(),
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let err = error {
            Logger.audio.error("Conversion error: \(err)")
            return
        }

        guard let channelData = output.floatChannelData else { return }
        let frameCount = Int(output.frameLength)
        queue.async { [weak self] in
            self?.samples.append(contentsOf: Array(UnsafeBufferPointer(start: channelData[0], count: frameCount)))
        }
    }

    private func whisperFormat() -> AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!
    }
}
```

**Note on the `convert` async:** The tap callback is the only writer to `samples`, so `queue.async` is correct — we're serializing against `stopRecording`'s `queue.sync`. No samples are lost; `stopRecording` only fires after `engine.stop()`, and the engine flushes its callback queue before returning from `stop()`. So by the time `stopRecording` reads under `queue.sync`, all pending `queue.async` blocks have finished.

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "AudioCapture|error:"
```

Expected: no errors.

- [ ] **Step 3: Smoke test**
  - Run `.build/debug/LocalVoice`
  - Hold Right Command, speak, release — transcription should work normally
  - Watch Console.app (filter `com.localvoice.app`) for any audio errors

- [ ] **Step 4: Commit**

```bash
git add Sources/LocalVoice/Audio/AudioCapture.swift
git commit -m "fix: synchronize AudioCapture samples with serial queue to prevent race condition"
```

---

## Task 4: Migrate remaining files to `os.Logger`

**Files:** Modify `TranscriptionEngine.swift`, `OllamaClient.swift`, `TextInserter.swift`

Mechanical swap of `debugLog(...)` → appropriate `Logger.*.*` calls.

- [ ] **Step 1: Replace TranscriptionEngine.swift**

```swift
import WhisperKit
import Foundation
import OSLog

final class TranscriptionEngine {
    private var whisper: WhisperKit?
    private var currentModel: String = "base"

    func loadModel(named model: String = "openai_whisper-large-v3_turbo") async {
        currentModel = model
        let name = TranscriptionEngine.displayName(for: model)
        do {
            let modelDir = try modelDirectory()
            if !modelAlreadyDownloaded(model, in: modelDir) {
                Logger.transcription.info("Downloading '\(name)' for the first time — this may take a minute...")
            }
            Logger.transcription.info("Loading model '\(name)'...")
            whisper = try await WhisperKit(model: model, downloadBase: modelDir)
            Logger.transcription.info("Ready.")
        } catch {
            Logger.transcription.error("Failed to load model '\(name)': \(error)")
        }
    }

    private func modelAlreadyDownloaded(_ model: String, in dir: URL) -> Bool {
        let coreMLDir = dir.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: coreMLDir.path)) ?? []
        return contents.contains { $0.localizedCaseInsensitiveContains(model) }
    }

    private func modelDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("LocalVoice/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func transcribe(buffer: [Float], language: String? = nil) async throws -> TranscriptionOutput {
        guard let whisper else {
            throw TranscriptionError.modelNotLoaded
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true
        )

        let results = try await whisper.transcribe(audioArray: buffer, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return TranscriptionOutput(text: text, language: results.first?.language)
    }

    // MARK: - Available models

    static let availableModels = ["tiny", "base", "small", "medium", "openai_whisper-large-v3_turbo", "large-v3"]

    static let modelDisplayNames: [String: String] = [
        "openai_whisper-large-v3_turbo": "large-v3-turbo",
    ]

    static func displayName(for model: String) -> String {
        modelDisplayNames[model] ?? model
    }
}

struct TranscriptionOutput {
    let text: String
    let language: String?
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not yet loaded. Please wait a moment."
        }
    }
}
```

- [ ] **Step 2: Replace OllamaClient.swift**

```swift
import Foundation
import OSLog

final class OllamaClient {
    private let baseURL = URL(string: "http://localhost:11434")!
    private let session: URLSession

    var model: String = DeviceCapability.recommendedGemmaModel

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    func rewrite(transcript: String, prompt: LLMPrompt, appContext: String?, detectedLanguage: String?) async throws -> String {
        var instruction = prompt.instruction
        if let lang = detectedLanguage,
           let displayName = Locale.current.localizedString(forLanguageCode: lang) {
            instruction += "\nRespond in \(displayName). Do NOT translate."
        } else {
            instruction += "\nRespond in the same language as the user's dictation. Do NOT translate."
        }
        if let ctx = appContext {
            instruction += "\nThe user is dictating into \(ctx). Preserve appropriate terminology and conventions."
        }
        instruction += "\n\nUser's dictation: \"\(transcript)\""

        return try await generate(prompt: instruction)
    }

    func generate(prompt: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OllamaRequest(model: model, prompt: prompt, stream: false)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw OllamaError.modelNotFound(model: model)
            }
            throw OllamaError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models.map(\.name)
    }

    func isAvailable() async -> Bool {
        guard let url = URL(string: "http://localhost:11434") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Codable models

private struct OllamaRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
}

private struct OllamaResponse: Decodable {
    let model: String
    let response: String
    let done: Bool
}

private struct OllamaTagsResponse: Decodable {
    struct ModelInfo: Decodable {
        let name: String
    }
    let models: [ModelInfo]
}

enum OllamaError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case modelNotFound(model: String)
    case notRunning

    var errorDescription: String? {
        switch self {
        case .invalidResponse:            return "Invalid response from Ollama"
        case .httpError(let code):        return "Ollama HTTP error: \(code)"
        case .modelNotFound(let model):   return "Model '\(model)' not pulled. Run: ollama pull \(model)"
        case .notRunning:                 return "Ollama is not running. Start it with: ollama serve"
        }
    }
}
```

- [ ] **Step 3: Replace TextInserter.swift**

```swift
import AppKit
import ApplicationServices
import OSLog

struct InsertionContext {
    let appName: String?
    let bundleID: String?
    let axRole: String?
    let isNativeField: Bool
}

/// Two-tier text insertion:
///   Tier 1 — kAXSelectedTextAttribute: inserts at cursor without reading existing content
///   Tier 2 — NSPasteboard + Cmd+V: universal fallback
final class TextInserter {
    private var capturedElement: AXUIElement?
    private var capturedApp: AXUIElement?
    private var capturedIsSecure: Bool = false

    // Call on hotkeyDown to lock in the target before focus shifts.
    func captureTarget() {
        capturedElement = nil
        capturedApp = nil
        capturedIsSecure = false

        let systemWide = AXUIElementCreateSystemWide()
        var appRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &appRef
        ) == .success, let appRef else { return }

        let app = appRef as! AXUIElement
        capturedApp = app

        var elementRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &elementRef
        ) == .success, let elementRef else { return }

        let element = elementRef as! AXUIElement
        capturedElement = element
        capturedIsSecure = axRole(element) == "AXSecureTextField"
    }

    // Returns AX-level context for debug logging. Does not affect insertion.
    func captureContext() -> InsertionContext {
        let front = NSWorkspace.shared.frontmostApplication
        let role = capturedElement.flatMap { axRole($0) }
        let nativeRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]
        return InsertionContext(
            appName: front?.localizedName,
            bundleID: front?.bundleIdentifier,
            axRole: role,
            isNativeField: role.map { nativeRoles.contains($0) } ?? false
        )
    }

    func insert(text: String) {
        guard !text.isEmpty else { return }

        if capturedIsSecure {
            Logger.textInserter.info("Secure text field — insert blocked")
            reset()
            return
        }

        let element = capturedElement
        let app = capturedApp
        reset()

        if AXIsProcessTrusted(), let el = element {
            Logger.textInserter.debug("Attempting AX insert...")
            let result = AXUIElementSetAttributeValue(
                el, kAXSelectedTextAttribute as CFString, text as CFTypeRef
            )
            if result == .success {
                var verifyRef: AnyObject?
                if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &verifyRef) == .success,
                   let verifiedValue = verifyRef as? String,
                   verifiedValue.contains(text) {
                    Logger.textInserter.debug("AX insert verified")
                    return
                }
                Logger.textInserter.info("AX reported success but text not found in field, falling back to pasteboard")
            } else {
                Logger.textInserter.info("AX insert failed (error: \(result.rawValue)), falling back to pasteboard")
            }
        } else {
            Logger.textInserter.debug("AX not available, using pasteboard")
        }

        pasteboardInsert(text: text, targetApp: app)
    }

    // MARK: - Tier 2: Pasteboard + Cmd+V

    private func pasteboardInsert(text: String, targetApp: AXUIElement?) {
        let pasteboard = NSPasteboard.general
        let previousContents: [(String, Data)] = pasteboard.pasteboardItems?.compactMap { item in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        var activationDelay = 0.0
        if let targetApp {
            var pid: pid_t = 0
            if AXUIElementGetPid(targetApp, &pid) == .success,
               let runningApp = NSRunningApplication(processIdentifier: pid) {
                Logger.textInserter.debug("Pasteboard: activating \(runningApp.localizedName ?? "app"), sending Cmd+V")
                runningApp.activate(options: [])
                activationDelay = 0.15
            }
        } else {
            Logger.textInserter.debug("Pasteboard: sending Cmd+V")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            let source = CGEventSource(stateID: .hidSystemState)
            let vKey: CGKeyCode = 0x09
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
            let up   = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags   = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard !previousContents.isEmpty else { return }
                pasteboard.clearContents()
                for (typeString, data) in previousContents {
                    pasteboard.setData(data, forType: NSPasteboard.PasteboardType(typeString))
                }
                Logger.textInserter.debug("Clipboard restored")
            }
        }
    }

    // MARK: - Helpers

    private func reset() {
        capturedElement = nil
        capturedApp = nil
        capturedIsSecure = false
    }

    private func axRole(_ element: AXUIElement) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
```

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | grep -E "error:|warning:"
```

Expected: no errors. There may be warnings about unused `import Foundation` in files that no longer need it — leave them, it's harmless.

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalVoice/Transcription/TranscriptionEngine.swift \
        Sources/LocalVoice/LLM/OllamaClient.swift \
        Sources/LocalVoice/TextInsertion/TextInserter.swift
git commit -m "refactor: migrate Transcription, OllamaClient, TextInserter logging to os.Logger"
```

---

## Task 5: Migrate AppDelegate & HotkeyManager to `os.Logger`

**Files:** Modify `Sources/LocalVoice/App/AppDelegate.swift`, `Sources/LocalVoice/Audio/HotkeyManager.swift`

- [ ] **Step 1: Update AppDelegate.swift logging calls**

Replace all `debugLog(...)` calls in AppDelegate.swift with `Logger.pipeline.*`:

```swift
// Line 47 — inside onHotkeyDown
Logger.pipeline.debug("[TextInserter] Target: \(ctx.appName ?? "unknown") (\(ctx.bundleID ?? "?")) — role: \(ctx.axRole ?? "none"), native: \(ctx.isNativeField)")

// Line 103
Logger.pipeline.debug("Audio buffer: \(buffer.count) samples")

// Line 108
Logger.pipeline.debug("Detected language: \(output.language ?? "unknown")")

// Line 109
Logger.pipeline.debug("Transcript: '\(output.text)'")

// Line 113
Logger.pipeline.debug("Empty transcript, skipping")

// Line 131 (language for rewrite)
Logger.pipeline.debug("Language for rewrite: \(languageForLLM ?? "unknown")")

// Line 143
Logger.pipeline.debug("Inserting: '\(finalText)'")

// Line 177
Logger.pipeline.error("Error: \(error)")
```

Also add `import OSLog` at the top of AppDelegate.swift and remove `import Combine` if it's only used for `cancellables` (keep it — it's needed for the `$whisperModel` sink).

- [ ] **Step 2: Update HotkeyManager.swift logging call**

The only `debugLog` in HotkeyManager is the event tap failure:

```swift
// In setupEventTap(), replace:
Logger.hotkey.error("Failed to create event tap. Check Input Monitoring permission.")
```

Add `import OSLog` at the top of HotkeyManager.swift.

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:"
```

Expected: zero errors. If there are any remaining `debugLog` references, fix them now.

- [ ] **Step 4: Confirm no remaining `debugLog` references**

```bash
grep -rn "debugLog" Sources/
```

Expected: no output (zero occurrences).

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalVoice/App/AppDelegate.swift \
        Sources/LocalVoice/Audio/HotkeyManager.swift
git commit -m "refactor: migrate AppDelegate and HotkeyManager logging to os.Logger"
```

---

## Task 6: Fix `try!` crash in AppDelegate SwiftData init

**Files:** Modify `Sources/LocalVoice/App/AppDelegate.swift`

`try! ModelContainer(for: TranscriptionRecord.self)` will hard-crash if SwiftData fails to initialize (e.g., corrupted store on disk, schema migration error after a model change). Replace it with a recoverable init that falls back gracefully.

- [ ] **Step 1: Replace ModelContainer initialization in `applicationDidFinishLaunching`**

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    do {
        modelContainer = try ModelContainer(for: TranscriptionRecord.self)
    } catch {
        Logger.persistence.error("SwiftData init failed: \(error) — history will be unavailable this session")
        // Continue without persistence. modelContainer stays nil; history window will be empty.
    }

    // rest of the method unchanged...
```

- [ ] **Step 2: Change `modelContainer` declaration to optional**

At the top of AppDelegate, change:

```swift
private var modelContainer: ModelContainer!
```

to:

```swift
private var modelContainer: ModelContainer?
```

- [ ] **Step 3: Guard the insert call in `stopAndProcess`**

In `stopAndProcess`, the `MainActor.run` block inserts a record. Guard it:

```swift
await MainActor.run {
    self.textInserter.insert(text: finalText)
    self.recordingOverlay.hide()

    if let container = self.modelContainer {
        let wordCount = finalText.split(separator: " ").count
        let record = TranscriptionRecord(
            timestamp: startTime,
            audioDurationSeconds: audioDuration,
            wordCount: wordCount,
            detectedLanguage: detectedLanguage,
            frontmostAppBundleID: targetApp?.bundleID,
            frontmostAppName: targetApp?.name,
            mode: mode.rawValue,
            whisperModel: whisperModel,
            ollamaModel: mode == .llmRewrite ? ollamaModel : nil,
            ollamaLatencySeconds: capturedOllamaLatency,
            transcribedText: saveText ? finalText : nil,
            promptName: capturedPromptName
        )
        container.mainContext.insert(record)
    }
}
```

- [ ] **Step 4: Guard `showHistory` against nil container**

```swift
func showHistory() {
    guard let modelContainer else {
        Logger.persistence.error("Cannot show history — SwiftData container unavailable")
        return
    }
    if historyWindow == nil {
        historyWindow = HistoryWindowController(modelContainer: modelContainer)
    }
    historyWindow?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | grep "error:"
```

Expected: zero errors.

- [ ] **Step 6: Commit**

```bash
git add Sources/LocalVoice/App/AppDelegate.swift
git commit -m "fix: replace try! ModelContainer with recoverable init — prevents crash on SwiftData failure"
```

---

## Task 7: Cancel in-flight transcription Task on new recording

**Files:** Modify `Sources/LocalVoice/App/AppDelegate.swift`

When a new recording starts while a previous `Task` (transcription + LLM + insert) is still running, both tasks complete and can race to insert text. Fix: store the `Task` handle and cancel it in `startRecording`.

- [ ] **Step 1: Add `currentPipelineTask` property to AppDelegate**

At the top of the class, after the other `private var` declarations:

```swift
private var currentPipelineTask: Task<Void, Never>?
```

- [ ] **Step 2: Cancel previous task in `startRecording`**

```swift
private func startRecording() {
    currentPipelineTask?.cancel()
    currentPipelineTask = nil

    recordingStartTime = Date()
    let ws = NSWorkspace.shared
    recordingTargetApp = ws.frontmostApplication.map {
        (bundleID: $0.bundleIdentifier ?? "unknown", name: $0.localizedName ?? "Unknown")
    }
    DispatchQueue.main.async { self.recordingOverlay.show(state: .recording) }
    audioCapture.startRecording()
}
```

- [ ] **Step 3: Assign the Task in `stopAndProcess`**

In `stopAndProcess`, wrap the `Task { ... }` and assign it:

```swift
currentPipelineTask = Task {
    do {
        // ... existing pipeline code unchanged ...
    } catch {
        Logger.pipeline.error("Error: \(error)")
        await MainActor.run { self.recordingOverlay.showError(error.localizedDescription) }
    }
}
```

- [ ] **Step 4: Add cancellation check after transcription**

Inside the Task, after the `transcribe` call completes, check for cancellation before proceeding to LLM:

```swift
let output = try await self.transcriptionEngine.transcribe(
    buffer: buffer,
    language: self.appSettings.transcriptionLanguage.whisperCode
)

try Task.checkCancellation()  // bail if a new recording started

Logger.pipeline.debug("Detected language: \(output.language ?? "unknown")")
```

Note: `Task.checkCancellation()` throws `CancellationError`, which is caught by the outer `do/catch`. The `catch` block calls `showError` — add a guard to avoid showing an error for intentional cancellation:

```swift
} catch is CancellationError {
    await MainActor.run { self.recordingOverlay.hide() }
} catch {
    Logger.pipeline.error("Error: \(error)")
    await MainActor.run { self.recordingOverlay.showError(error.localizedDescription) }
}
```

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | grep "error:"
```

Expected: zero errors.

- [ ] **Step 6: Smoke test**
  - Run `.build/debug/LocalVoice`
  - Start a recording (hold Right Command), release immediately to trigger transcription
  - While Whisper is running, start a new recording
  - Confirm: only the second recording's text is inserted, no double-insertion

- [ ] **Step 7: Commit**

```bash
git add Sources/LocalVoice/App/AppDelegate.swift
git commit -m "fix: cancel in-flight pipeline Task when new recording starts"
```

---

## Task 8: Log PromptStore save errors

**Files:** Modify `Sources/LocalVoice/LLM/PromptStore.swift`

The `save()` method silently swallows both `JSONEncoder` and `Data.write` failures. Add `os.Logger` and log at error level if either step fails.

- [ ] **Step 1: Replace PromptStore.swift**

```swift
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
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep "error:"
```

Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/LocalVoice/LLM/PromptStore.swift
git commit -m "fix: log PromptStore save errors instead of swallowing them silently"
```

---

## Task 9: Connect `hotkeyKeyCode` AppSettings to HotkeyManager

**Files:** Modify `Sources/LocalVoice/App/AppDelegate.swift`, `Sources/LocalVoice/Audio/HotkeyManager.swift`

`AppSettings.hotkeyKeyCode` is stored in UserDefaults but `HotkeyManager.monitoredKeyCode` is never updated from it. Wire them up: apply the saved value at startup, and observe changes via Combine.

- [ ] **Step 1: Apply saved key code at HotkeyManager init in `applicationDidFinishLaunching`**

In AppDelegate, after `hotkeyManager = HotkeyManager()`, add:

```swift
hotkeyManager.monitoredKeyCode = appSettings.hotkeyKeyCode
```

- [ ] **Step 2: Observe `hotkeyKeyCode` changes in AppDelegate**

In `applicationDidFinishLaunching`, alongside the existing `$whisperModel` sink, add:

```swift
appSettings.$hotkeyKeyCode
    .dropFirst()
    .sink { [weak self] keyCode in
        self?.hotkeyManager.monitoredKeyCode = keyCode
    }
    .store(in: &cancellables)
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:"
```

Expected: zero errors.

- [ ] **Step 4: Smoke test**
  - Check that `AppSettings.hotkeyKeyCode` defaults to `63` (Right Option, `0x3F`)
  - Verify this matches the key configured in Settings
  - Confirm hotkey still works after restart

- [ ] **Step 5: Commit**

```bash
git add Sources/LocalVoice/App/AppDelegate.swift
git commit -m "fix: wire AppSettings.hotkeyKeyCode to HotkeyManager.monitoredKeyCode at startup and on change"
```

---

## Task 10: Final build and end-to-end smoke test

- [ ] **Step 1: Full clean build**

```bash
swift build -c release 2>&1 | tail -5
```

Expected: `Build complete!`

- [ ] **Step 2: Run and verify Console.app integration**

  1. Open Console.app (Spotlight → Console)
  2. In the search bar, type: `subsystem:com.localvoice.app`
  3. Run `.build/release/LocalVoice`
  4. Hold Right Command → speak → release
  5. Confirm Console.app shows structured log entries for Pipeline, Transcription, etc.
  6. Confirm text is inserted in the frontmost app

- [ ] **Step 3: Verify no remaining legacy patterns**

```bash
grep -rn "debugLog\|Config.debugLogging\|import.*Config" Sources/
```

Expected: no output.

- [ ] **Step 4: Final commit tag (optional)**

```bash
git log --oneline -10
```

Review that all 9 commits from this plan are present and sequential.

---

## Verification Summary

| Fix | How to verify |
|---|---|
| os.Logger migration | Console.app shows `com.localvoice.app` entries during recording |
| No `debugLog` remaining | `grep -rn "debugLog" Sources/` returns nothing |
| AudioCapture race | Normal recording works; no crashes under rapid start/stop |
| ModelContainer crash fix | `modelContainer` is now optional; `try!` removed |
| Task cancellation | Start recording, immediately start another — only second text inserted |
| PromptStore errors logged | Errors from save appear in Console.app under `Persistence` category |
| hotkeyKeyCode wired | Changing key code in Settings takes effect without restart |
