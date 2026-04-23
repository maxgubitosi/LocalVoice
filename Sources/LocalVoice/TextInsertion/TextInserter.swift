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
                Logger.textInserter.warning("AX reported success but text not found in field — falling back to pasteboard")
            } else {
                Logger.textInserter.warning("AX insert failed (error: \(result.rawValue)) — falling back to pasteboard")
            }
        } else {
            Logger.textInserter.debug("AX not available — using pasteboard")
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
            Logger.textInserter.debug("Pasteboard: no target app captured — sending Cmd+V")
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
