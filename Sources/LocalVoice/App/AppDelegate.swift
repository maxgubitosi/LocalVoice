import AppKit
import AVFoundation
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager!
    private var hotkeyManager: HotkeyManager!
    private var audioCapture: AudioCapture!
    private var transcriptionEngine: TranscriptionEngine!
    private var ollamaClient: OllamaClient!
    private var textInserter: TextInserter!
    private var recordingOverlay: RecordingOverlayWindow!
    private var cancellables = Set<AnyCancellable>()

    var appSettings = AppSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()

        transcriptionEngine = TranscriptionEngine()
        ollamaClient = OllamaClient()
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
        // Microphone
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        // Accessibility — prompt if not already granted
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    private func startRecording() {
        DispatchQueue.main.async { self.recordingOverlay.show() }
        audioCapture.startRecording()
    }

    private func stopAndProcess() {
        audioCapture.stopRecording { [weak self] audioBuffer in
            guard let self else { return }
            DispatchQueue.main.async { self.recordingOverlay.hide() }

            guard let buffer = audioBuffer else { return }

            Task {
                do {
                    print("[Pipeline] Audio buffer: \(buffer.count) samples")
                    let transcript = try await self.transcriptionEngine.transcribe(
                        buffer: buffer,
                        language: self.appSettings.transcriptionLanguage.whisperCode
                    )
                    print("[Pipeline] Transcript: '\(transcript)'")
                    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        print("[Pipeline] Empty transcript, skipping")
                        return
                    }

                    let finalText: String
                    if self.appSettings.mode == .llmRewrite {
                        finalText = try await self.ollamaClient.rewrite(transcript: transcript)
                    } else {
                        finalText = transcript
                    }

                    print("[Pipeline] Inserting: '\(finalText)'")
                    await MainActor.run { self.textInserter.insert(text: finalText) }
                } catch {
                    print("[Pipeline] Error: \(error)")
                    await MainActor.run {
                        self.menuBarManager.showError(error.localizedDescription)
                    }
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
    }
    func whisperModelChanged(to model: String) {
        appSettings.whisperModel = model
        Task { await transcriptionEngine.loadModel(named: model) }
    }
    func languageChanged(to language: TranscriptionLanguage) {
        appSettings.transcriptionLanguage = language
    }
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
