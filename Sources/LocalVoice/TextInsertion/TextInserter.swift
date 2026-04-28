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
///   Tier 2 — Unicode keyboard events: no clipboard access
final class TextInserter {
    private enum KeyboardFallback {
        static let activationPollInterval: TimeInterval = 0.05
        static let activationTimeout: TimeInterval = 0.8
        static let maxUTF16UnitsPerEvent = 64
    }

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
            Logger.textInserter.debug("Attempting AX insert…")
            let result = AXUIElementSetAttributeValue(
                el, kAXSelectedTextAttribute as CFString, text as CFTypeRef
            )
            if result == .success {
                // Some apps (Electron/Chromium) report success but don't actually update the field.
                // Read back the value to confirm the text landed.
                var verifyRef: AnyObject?
                if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &verifyRef) == .success,
                   let verifiedValue = verifyRef as? String,
                   verifiedValue.contains(text) {
                    Logger.textInserter.debug("AX insert verified")
                    return
                }
                Logger.textInserter.warning("AX reported success but text not found in field — falling back to keyboard events")
            } else {
                Logger.textInserter.warning("AX insert failed (error: \(result.rawValue)) — falling back to keyboard events")
            }
        } else {
            Logger.textInserter.debug("AX not available — using keyboard events")
        }

        keyboardInsert(text: text, targetApp: app)
    }

    // MARK: - Tier 2: Unicode Keyboard Events

    private func keyboardInsert(text: String, targetApp: AXUIElement?) {
        var targetPID: pid_t?
        if let targetApp {
            var pid: pid_t = 0
            if AXUIElementGetPid(targetApp, &pid) == .success,
               let runningApp = NSRunningApplication(processIdentifier: pid) {
                Logger.textInserter.debug("Keyboard fallback: activating \(runningApp.localizedName ?? "app")")
                runningApp.activate(options: [])
                targetPID = pid
            }
        } else {
            Logger.textInserter.debug("Keyboard fallback: no target app captured")
        }

        waitForTargetActivation(pid: targetPID, startedAt: Date()) {
            self.typeUnicode(text)
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

    private func waitForTargetActivation(pid: pid_t?, startedAt: Date, _ completion: @escaping () -> Void) {
        guard let pid else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid ||
            Date().timeIntervalSince(startedAt) >= KeyboardFallback.activationTimeout {
            completion()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardFallback.activationPollInterval) {
            self.waitForTargetActivation(pid: pid, startedAt: startedAt, completion)
        }
    }

    private func typeUnicode(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for chunk in unicodeChunks(for: text) {
            let utf16 = Array(chunk.utf16)
            utf16.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                down?.post(tap: .cghidEventTap)
                up?.post(tap: .cghidEventTap)
            }
        }
    }

    private func unicodeChunks(for text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var currentCount = 0

        for character in text {
            let characterString = String(character)
            let characterCount = characterString.utf16.count
            if currentCount > 0,
               currentCount + characterCount > KeyboardFallback.maxUTF16UnitsPerEvent {
                chunks.append(current)
                current = ""
                currentCount = 0
            }

            current.append(character)
            currentCount += characterCount
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}
