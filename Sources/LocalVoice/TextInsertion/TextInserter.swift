import AppKit
import ApplicationServices

/// Two-tier text insertion:
///   Tier 1 — AXUIElement (Accessibility API): precise, no clipboard pollution
///   Tier 2 — NSPasteboard + Cmd+V: universal fallback
final class TextInserter {
    private var capturedElement: AXUIElement?
    private var capturedApp: AXUIElement?

    // Call this on hotkeyDown, before recording starts, to lock in the target element
    func captureTarget() {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success, let app = focusedApp else { return }

        capturedApp = (app as! AXUIElement)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement
        ) == .success else { return }

        capturedElement = (focusedElement as! AXUIElement)
    }

    func insert(text: String) {
        guard !text.isEmpty else { return }

        debugLog("[TextInserter] AX trusted: \(AXIsProcessTrusted())")
        if tryAccessibilityInsert(text: text) {
            debugLog("[TextInserter] Inserted via AX")
            capturedElement = nil
            capturedApp = nil
            return
        }
        debugLog("[TextInserter] AX failed, falling back to pasteboard")
        let targetApp = capturedApp
        capturedElement = nil
        capturedApp = nil
        pasteboardInsert(text: text, targetApp: targetApp)
    }

    // MARK: - Tier 1: Accessibility API

    private func tryAccessibilityInsert(text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        guard let focusedElement = capturedElement ?? focusedAXElement() else { return false }
        guard !isSecureTextField(focusedElement) else {
            debugLog("[TextInserter] Skipping secure text field")
            return false
        }
        guard isNativeTextField(focusedElement) else {
            debugLog("[TextInserter] Non-native field (Electron/web), using pasteboard")
            return false
        }

        // Get current value
        var currentValueRef: AnyObject?
        let getResult = AXUIElementCopyAttributeValue(
            focusedElement, kAXValueAttribute as CFString, &currentValueRef
        )

        if getResult == .success, let current = currentValueRef as? String {
            // Append at insertion point
            var selectedRangeValue: AnyObject?
            AXUIElementCopyAttributeValue(
                focusedElement, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue
            )

            var range = CFRange(location: current.count, length: 0)
            if let rangeValue = selectedRangeValue,
               CFGetTypeID(rangeValue) == AXValueGetTypeID(),
               let axValue = rangeValue as! AXValue? {
                AXValueGetValue(axValue, .cfRange, &range)
            }

            let nsString = current as NSString
            let prefix = nsString.substring(to: min(range.location, nsString.length))
            let suffix = nsString.substring(from: min(range.location + range.length, nsString.length))
            let newValue = prefix + text + suffix

            let setResult = AXUIElementSetAttributeValue(
                focusedElement, kAXValueAttribute as CFString, newValue as CFTypeRef
            )
            if setResult == .success {
                // Verify the write actually took effect (Chromium/Electron reports false success)
                var verifyRef: AnyObject?
                guard AXUIElementCopyAttributeValue(
                    focusedElement, kAXValueAttribute as CFString, &verifyRef
                ) == .success, (verifyRef as? String) == newValue else {
                    debugLog("[TextInserter] AX write unverified (Electron false-success), using pasteboard")
                    return false
                }

                let newPos = range.location + text.count
                var cfRange = CFRange(location: newPos, length: 0)
                if let newRange = AXValueCreate(.cfRange, &cfRange) {
                    AXUIElementSetAttributeValue(
                        focusedElement, kAXSelectedTextRangeAttribute as CFString, newRange
                    )
                }
                return true
            }
        }

        // Fields that don't expose kAXValueAttribute may support kAXSelectedTextAttribute
        let insertResult = AXUIElementSetAttributeValue(
            focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        if insertResult != .success { return false }

        // Verify via value read-back; if unverifiable, fall through to pasteboard
        var verifyRef: AnyObject?
        if AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &verifyRef) == .success,
           let verifiedValue = verifyRef as? String {
            return verifiedValue.contains(text)
        }
        return false
    }

    private func focusedAXElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success else { return nil }

        guard let app = focusedApp else { return nil }
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement
        ) == .success else { return nil }

        return (focusedElement as! AXUIElement)
    }

    private func axRole(_ element: AXUIElement) -> String? {
        var roleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleRef
        ) == .success else { return nil }
        return roleRef as? String
    }

    private func isSecureTextField(_ element: AXUIElement) -> Bool {
        axRole(element) == "AXSecureTextField"
    }

    private func isNativeTextField(_ element: AXUIElement) -> Bool {
        guard let role = axRole(element) else { return false }
        return role == "AXTextField" || role == "AXTextArea"
            || role == "AXSearchField" || role == "AXComboBox"
    }

    // MARK: - Tier 2: Clipboard + Cmd+V

    private func pasteboardInsert(text: String, targetApp: AXUIElement? = nil) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.pasteboardItems?.compactMap { item -> (String, NSData)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data as NSData)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Activate the target app so Cmd+V lands in the right place
        var activationDelay = 0.0
        if let targetApp {
            var pid: pid_t = 0
            if AXUIElementGetPid(targetApp, &pid) == .success,
               let app = NSRunningApplication(processIdentifier: pid) {
                app.activate(options: [])
                activationDelay = 0.15
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            let source = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: CGKeyCode = 0x09
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags   = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            // Restore original clipboard after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let previous = previousContents, !previous.isEmpty {
                    pasteboard.clearContents()
                    for (typeString, data) in previous {
                        pasteboard.setData(data as Data, forType: NSPasteboard.PasteboardType(typeString))
                    }
                }
            }
        }
    }
}
