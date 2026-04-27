import AppKit
import AVFoundation
import ApplicationServices

enum PermissionManager {
    struct Snapshot {
        let microphone: Bool
        let accessibility: Bool
        let inputMonitoring: Bool

        var allGranted: Bool {
            microphone && accessibility && inputMonitoring
        }
    }

    static func current() -> Snapshot {
        Snapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: inputMonitoringGranted()
        )
    }

    static func requestMissingPermissions() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options)

        if #available(macOS 10.15, *) {
            _ = CGRequestListenEventAccess()
        }
    }

    static func openMicrophoneSettings() {
        openSettingsPane("Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        openSettingsPane("Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        openSettingsPane("Privacy_ListenEvent")
    }

    private static func inputMonitoringGranted() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    private static func openSettingsPane(_ privacyPane: String) {
        if let directURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacyPane)") {
            NSWorkspace.shared.open(directURL)
        }
    }
}
