import AppKit
import AVFoundation
import Combine
import OSLog
import Sparkle
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updaterController: SPUStandardUpdaterController!
    private var menuBarManager: MenuBarManager!
    private var hotkeyManager: HotkeyManager!
    private var audioCapture: AudioCapture!
    private var transcriptionEngine: TranscriptionEngine!
    private var mlxClient: MLXClient!
    private var mlxModelManager: MLXModelManager!
    private var textInserter: TextInserter!
    private var recordingOverlay: RecordingOverlayWindow!
    private var historyWindow: HistoryWindowController?
    private var settingsWindow: SettingsWindowController?
    private var firstRunWindow: FirstRunWindowController?
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

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

        transcriptionEngine = TranscriptionEngine()
        mlxClient = MLXClient()
        mlxClient.modelID = appSettings.llmModel
        mlxModelManager = MLXModelManager()
        promptStore = PromptStore()
        textInserter = TextInserter()
        audioCapture = AudioCapture()
        recordingOverlay = RecordingOverlayWindow()
        menuBarManager = MenuBarManager(settings: appSettings, promptStore: promptStore, delegate: self, updaterController: updaterController)
        hotkeyManager = HotkeyManager()
        hotkeyManager.recordingHotkey = appSettings.recordingHotkey

        hotkeyManager.onHotkeyDown = { [weak self] in
            // Everything on main thread: captureTarget() does AX IPC, startRecording() touches
            // app state. Calling either from the CG event tap thread causes race conditions.
            DispatchQueue.main.async {
                self?.textInserter.captureTarget()
                if let ctx = self?.textInserter.captureContext() {
                    Logger.textInserter.debug("Target: \(ctx.appName ?? "unknown") (\(ctx.bundleID ?? "?")) — role: \(ctx.axRole ?? "none"), native: \(ctx.isNativeField)")
                }
                self?.startRecording()
            }
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

        appSettings.$llmModel
            .dropFirst()
            .sink { [weak self] model in
                self?.mlxClient.modelID = model
            }
            .store(in: &cancellables)

        appSettings.$recordingHotkey
            .dropFirst()
            .sink { [weak self] hotkey in
                self?.hotkeyManager.recordingHotkey = hotkey
            }
            .store(in: &cancellables)

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            showFirstRunWindow()
        }
    }

    private func showFirstRunWindow() {
        let mlxModelID = appSettings.llmModel
        let whisperModel = appSettings.whisperModel
        firstRunWindow = FirstRunWindowController(
            transcriptionEngine: transcriptionEngine,
            mlxModelManager: mlxModelManager,
            whisperModel: whisperModel,
            mlxModelID: mlxModelID,
            onComplete: { [weak self] in
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                self?.firstRunWindow?.close()
                self?.firstRunWindow = nil
            }
        )
        firstRunWindow?.showWindow(nil)

        Task {
            if DeviceCapability.physicalMemoryGB >= 16 {
                async let whisperLoad: Void = await transcriptionEngine.loadModel(named: whisperModel)
                async let mlxDownload: Void = try await mlxModelManager.downloadModel(mlxModelID)
                _ = try await (whisperLoad, mlxDownload)
            } else {
                await transcriptionEngine.loadModel(named: whisperModel)
                try? await mlxModelManager.downloadModel(mlxModelID)
            }
        }
    }

    private func requestPermissions() {
        PermissionManager.requestMissingPermissions()
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

            let processingStart = Date()
            self.currentPipelineTask = Task {
                do {
                    Logger.pipeline.debug("Audio buffer: \(buffer.count) samples")
                    let transcriptionStart = Date()
                    let output = try await self.transcriptionEngine.transcribe(
                        buffer: buffer,
                        language: self.appSettings.transcriptionLanguage.whisperCode
                    )
                    let transcriptionLatency = Date().timeIntervalSince(transcriptionStart)
                    try Task.checkCancellation()
                    Logger.pipeline.debug("Detected language: \(output.language ?? "unknown")")
                    Logger.pipeline.debug("Transcript: '\(output.text)'")
                    guard !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        Logger.pipeline.info("Empty transcript — skipping")
                        await MainActor.run { self.recordingOverlay.hide() }
                        return
                    }

                    let isMLXDownloaded = await self.mlxModelManager.isDownloaded(self.appSettings.llmModel)
                    if self.appSettings.mode == .llmRewrite && !self.mlxClient.isLLMModelLoaded
                        && !isMLXDownloaded {
                        await MainActor.run {
                            self.recordingOverlay.showError("LLM model not downloaded. Open Settings to download it.")
                        }
                        return
                    }

                    let activePrompt: LLMPrompt
                    if let n = capturedKeyNumber, let p = self.promptStore.prompt(withKeyNumber: n) {
                        activePrompt = p
                    } else {
                        activePrompt = self.promptStore.activePrompt(id: self.appSettings.activePromptID)
                    }

                    let finalText: String
                    var llmLatency: Double? = nil

                    if self.appSettings.mode == .llmRewrite {
                        await MainActor.run {
                            self.recordingOverlay.showRefining(promptName: activePrompt.name, transcript: output.text)
                        }
                        let llmStart = Date()
                        let languageForLLM = output.language
                        Logger.pipeline.debug("Language for rewrite: \(languageForLLM ?? "unknown", privacy: .public)")
                        let refinedText = try await self.mlxClient.rewrite(
                            transcript: output.text,
                            prompt: activePrompt,
                            appContext: self.recordingTargetApp?.name,
                            detectedLanguage: languageForLLM
                        )
                        finalText = RefineOutputSanitizer.clean(refinedText)
                        llmLatency = Date().timeIntervalSince(llmStart)
                    } else {
                        finalText = output.text
                    }

                    try Task.checkCancellation()
                    Logger.pipeline.debug("Inserting: '\(finalText)'")
                    let startTime = self.recordingStartTime
                    let targetApp = self.recordingTargetApp
                    let mode = self.appSettings.mode
                    let whisperModel = TranscriptionEngine.displayName(for: self.appSettings.whisperModel)
                    let llmModel = self.appSettings.llmModel
                    let saveText = self.appSettings.saveTranscribedText
                    let detectedLanguage = output.language
                    let capturedLLMLatency = llmLatency
                    let capturedTranscriptionLatency = transcriptionLatency
                    let audioDuration = Double(buffer.count) / 16000.0
                    let capturedPromptName: String? = mode == .llmRewrite ? activePrompt.name : nil
                    let capturedTranscribedText = saveText ? output.text : nil
                    let capturedOriginalText = saveText ? output.text : nil
                    let capturedRefinedText = saveText && mode == .llmRewrite ? finalText : nil

                    await MainActor.run {
                        let processingLatency = Date().timeIntervalSince(processingStart)
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
                                llmModel: mode == .llmRewrite ? llmModel : nil,
                                llmLatencySeconds: capturedLLMLatency,
                                transcribedText: capturedTranscribedText,
                                originalText: capturedOriginalText,
                                refinedText: capturedRefinedText,
                                transcriptionLatencySeconds: capturedTranscriptionLatency,
                                processingLatencySeconds: processingLatency,
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
    func llmModelChanged(to model: String) {
        appSettings.llmModel = model
        mlxClient.modelID = model
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
            settingsWindow = SettingsWindowController(
                settings: appSettings,
                promptStore: promptStore,
                mlxModelManager: mlxModelManager,
                transcriptionEngine: transcriptionEngine
            )
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
