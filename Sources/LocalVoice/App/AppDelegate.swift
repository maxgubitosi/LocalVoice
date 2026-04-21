import AppKit
import AVFoundation
import Combine
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
    private var cancellables = Set<AnyCancellable>()

    private var modelContainer: ModelContainer!
    private var recordingStartTime: Date = Date()
    private var recordingTargetApp: (bundleID: String, name: String)? = nil

    var appSettings = AppSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        modelContainer = try! ModelContainer(for: TranscriptionRecord.self)

        requestPermissions()

        transcriptionEngine = TranscriptionEngine()
        ollamaClient = OllamaClient()
        ollamaClient.model = appSettings.ollamaModel
        textInserter = TextInserter()
        audioCapture = AudioCapture()
        recordingOverlay = RecordingOverlayWindow()
        menuBarManager = MenuBarManager(settings: appSettings, delegate: self)
        hotkeyManager = HotkeyManager()

        hotkeyManager.onHotkeyDown = { [weak self] in
            // captureTarget() hace IPC vía AX — no llamarla desde el tap callback directamente
            // para no bloquear el run loop y que macOS no deshabilite el tap.
            DispatchQueue.main.async { self?.textInserter.captureTarget() }
            self?.startRecording()
        }
        hotkeyManager.onHotkeyUp   = { [weak self] in self?.stopAndProcess() }

        Task { await transcriptionEngine.loadModel(named: appSettings.whisperModel) }
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Accessibility — prompt if not already granted
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func startRecording() {
        recordingStartTime = Date()
        let ws = NSWorkspace.shared
        recordingTargetApp = ws.frontmostApplication.map {
            (bundleID: $0.bundleIdentifier ?? "unknown", name: $0.localizedName ?? "Unknown")
        }
        DispatchQueue.main.async { self.recordingOverlay.show(state: .recording) }
        audioCapture.startRecording()
    }

    private func stopAndProcess() {
        audioCapture.stopRecording { [weak self] audioBuffer in
            guard let self else { return }
            DispatchQueue.main.async { self.recordingOverlay.showTranscribing() }

            guard let buffer = audioBuffer else {
                DispatchQueue.main.async { self.recordingOverlay.hide() }
                return
            }

            Task {
                do {
                    print("[Pipeline] Audio buffer: \(buffer.count) samples")
                    let output = try await self.transcriptionEngine.transcribe(
                        buffer: buffer,
                        language: self.appSettings.transcriptionLanguage.whisperCode
                    )
                    print("[Pipeline] Transcript: '\(output.text)'")
                    guard !output.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("[Pipeline] Empty transcript, skipping")
                        await MainActor.run { self.recordingOverlay.hide() }
                        return
                    }

                    let finalText: String
                    var ollamaLatency: Double? = nil

                    if self.appSettings.mode == .llmRewrite {
                        await MainActor.run { self.recordingOverlay.showRefining(transcript: output.text) }
                        let ollamaStart = Date()
                        finalText = try await self.ollamaClient.rewrite(transcript: output.text)
                        ollamaLatency = Date().timeIntervalSince(ollamaStart)
                    } else {
                        finalText = output.text
                    }

                    print("[Pipeline] Inserting: '\(finalText)'")
                    let startTime = self.recordingStartTime
                    let targetApp = self.recordingTargetApp
                    let mode = self.appSettings.mode
                    let whisperModel = self.appSettings.whisperModel
                    let ollamaModel = self.appSettings.ollamaModel
                    let saveText = self.appSettings.saveTranscribedText
                    let detectedLanguage = output.language
                    let capturedOllamaLatency = ollamaLatency
                    let audioDuration = Double(buffer.count) / 16000.0

                    await MainActor.run {
                        self.textInserter.insert(text: finalText)
                        self.recordingOverlay.hide()

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
                            transcribedText: saveText ? finalText : nil
                        )
                        self.modelContainer.mainContext.insert(record)
                    }
                } catch {
                    print("[Pipeline] Error: \(error)")
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
        Task { await transcriptionEngine.loadModel(named: model) }
    }
    func languageChanged(to language: TranscriptionLanguage) {
        appSettings.transcriptionLanguage = language
    }
    func showHistory() {
        if historyWindow == nil {
            historyWindow = HistoryWindowController(modelContainer: modelContainer)
        }
        historyWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
