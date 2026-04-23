import AppKit
import AVFoundation
import Combine
import OSLog
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager!
    private var hotkeyManager: HotkeyManager!
    private var audioCapture: AudioCapture!
    private var transcriptionEngine: TranscriptionEngine!
    private var ollamaClient: OllamaClient!
    private var textInserter: TextInserter!
    private var recordingOverlay: RecordingOverlayWindow!
    private var historyWindow: HistoryWindowController?
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    private var modelContainer: ModelContainer?
    private var recordingStartTime: Date = Date()
    private var recordingTargetApp: (bundleID: String, name: String)? = nil
    private var promptStore: PromptStore!
    private var sessionPromptKeyNumber: Int? = nil
    private var currentPipelineTask: Task<Void, Never>?

    var appSettings = AppSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            modelContainer = try ModelContainer(for: TranscriptionRecord.self)
        } catch {
            Logger.persistence.error("SwiftData init failed: \(error) — history will be unavailable this session")
        }

        requestPermissions()

        transcriptionEngine = TranscriptionEngine()
        ollamaClient = OllamaClient()
        ollamaClient.model = appSettings.ollamaModel
        promptStore = PromptStore()
        textInserter = TextInserter()
        audioCapture = AudioCapture()
        recordingOverlay = RecordingOverlayWindow()
        menuBarManager = MenuBarManager(settings: appSettings, promptStore: promptStore, delegate: self)
        hotkeyManager = HotkeyManager()
        hotkeyManager.monitoredKeyCode = CGKeyCode(appSettings.hotkeyKeyCode)

        hotkeyManager.onHotkeyDown = { [weak self] in
            // captureTarget() hace IPC vía AX — no llamarla desde el tap callback directamente
            // para no bloquear el run loop y que macOS no deshabilite el tap.
            DispatchQueue.main.async {
                self?.textInserter.captureTarget()
                if let ctx = self?.textInserter.captureContext() {
                    Logger.textInserter.debug("Target: \(ctx.appName ?? "unknown") (\(ctx.bundleID ?? "?")) — role: \(ctx.axRole ?? "none"), native: \(ctx.isNativeField)")
                }
            }
            self?.startRecording()
        }
        hotkeyManager.onHotkeyUp     = { [weak self] in self?.stopAndProcess() }
        hotkeyManager.onHotkeyCancel = { [weak self] in self?.cancelRecording() }
        hotkeyManager.onPromptKeyPressed = { [weak self] n in self?.sessionPromptKeyNumber = n }

        transcriptionEngine.$isModelLoaded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loaded in
                self?.menuBarManager.setLoading(!loaded)
            }
            .store(in: &cancellables)

        Task { await transcriptionEngine.loadModel(named: appSettings.whisperModel) }

        appSettings.$whisperModel
            .dropFirst()
            .sink { [weak self] model in
                Task { await self?.transcriptionEngine.loadModel(named: model) }
            }
            .store(in: &cancellables)

        appSettings.$hotkeyKeyCode
            .dropFirst()
            .sink { [weak self] keyCode in
                self?.hotkeyManager.monitoredKeyCode = CGKeyCode(keyCode)
            }
            .store(in: &cancellables)
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Accessibility — prompt if not already granted
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func cancelRecording() {
        audioCapture.stopRecording { _ in }
        DispatchQueue.main.async { self.recordingOverlay.hide() }
    }

    private func startRecording() {
        guard transcriptionEngine.isModelLoaded else {
            recordingOverlay.showError("Loading model, please wait…")
            return
        }
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

    private func stopAndProcess() {
        let capturedKeyNumber = sessionPromptKeyNumber
        sessionPromptKeyNumber = nil
        audioCapture.stopRecording { [weak self] audioBuffer in
            guard let self else { return }
            DispatchQueue.main.async { self.recordingOverlay.showTranscribing() }

            guard let buffer = audioBuffer else {
                DispatchQueue.main.async { self.recordingOverlay.hide() }
                return
            }

            self.currentPipelineTask = Task {
                do {
                    Logger.pipeline.debug("Audio buffer: \(buffer.count) samples")
                    let output = try await self.transcriptionEngine.transcribe(
                        buffer: buffer,
                        language: self.appSettings.transcriptionLanguage.whisperCode
                    )
                    try Task.checkCancellation()
                    Logger.pipeline.debug("Detected language: \(output.language ?? "unknown")")
                    Logger.pipeline.debug("Transcript: '\(output.text)'")
                    guard !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        Logger.pipeline.info("Empty transcript — skipping")
                        await MainActor.run { self.recordingOverlay.hide() }
                        return
                    }

                    let activePrompt: LLMPrompt
                    if let n = capturedKeyNumber, let p = self.promptStore.prompt(withKeyNumber: n) {
                        activePrompt = p
                    } else {
                        activePrompt = self.promptStore.activePrompt(id: self.appSettings.activePromptID)
                    }

                    let finalText: String
                    var ollamaLatency: Double? = nil

                    if self.appSettings.mode == .llmRewrite {
                        await MainActor.run { self.recordingOverlay.showRefining(transcript: output.text) }
                        let ollamaStart = Date()
                        // Prefer the user-configured language over Whisper's auto-detection (which can misidentify).
                        let languageForLLM = self.appSettings.transcriptionLanguage.whisperCode ?? output.language
                        Logger.pipeline.debug("Language for rewrite: \(languageForLLM ?? "unknown")")
                        finalText = try await self.ollamaClient.rewrite(
                            transcript: output.text,
                            prompt: activePrompt,
                            appContext: self.recordingTargetApp?.name,
                            detectedLanguage: languageForLLM
                        )
                        ollamaLatency = Date().timeIntervalSince(ollamaStart)
                    } else {
                        finalText = output.text
                    }

                    Logger.pipeline.debug("Inserting: '\(finalText)'")
                    let startTime = self.recordingStartTime
                    let targetApp = self.recordingTargetApp
                    let mode = self.appSettings.mode
                    let whisperModel = TranscriptionEngine.displayName(for: self.appSettings.whisperModel)
                    let ollamaModel = self.appSettings.ollamaModel
                    let saveText = self.appSettings.saveTranscribedText
                    let detectedLanguage = output.language
                    let capturedOllamaLatency = ollamaLatency
                    let audioDuration = Double(buffer.count) / 16000.0
                    let capturedPromptName: String? = mode == .llmRewrite ? activePrompt.name : nil

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
                } catch is CancellationError {
                    await MainActor.run { self.recordingOverlay.hide() }
                } catch {
                    Logger.pipeline.error("Pipeline error: \(error)")
                    await MainActor.run { self.recordingOverlay.showError(error.localizedDescription) }
                }
            }
        }
    }
}

extension AppDelegate: MenuBarDelegate {
    func modeChanged(to mode: AppMode) {
        appSettings.mode = mode
    }
    func ollamaModelChanged(to model: String) {
        appSettings.ollamaModel = model
        ollamaClient.model = model
    }
    func whisperModelChanged(to model: String) {
        appSettings.whisperModel = model
    }
    func languageChanged(to language: TranscriptionLanguage) {
        appSettings.transcriptionLanguage = language
    }
    func promptChanged(to id: UUID) {
        appSettings.activePromptID = id
    }
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
    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: appSettings, promptStore: promptStore)
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
