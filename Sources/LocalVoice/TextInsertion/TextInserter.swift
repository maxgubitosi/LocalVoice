import AppKit
import ApplicationServices

/// Two-tier text insertion:
///   Tier 1 — AXUIElement (Accessibility API): precise, no clipboard pollution
///   Tier 2 — NSPasteboard + Cmd+V: universal fallback
final class TextInserter {

    func insert(text: String) {
        guard !text.isEmpty else { return }

        if tryAccessibilityInsert(text: text) { return }
        pasteboardInsert(text: text)
    }

    // MARK: - Tier 1: Accessibility API

    private func tryAccessibilityInsert(text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        guard let focusedElement = focusedAXElement() else { return false }
        guard !isSecureTextField(focusedElement) else {
            print("[TextInserter] Skipping secure text field")
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
                // Move caret to end of inserted text
                let newPos = range.location + text.count
                if let newRange = AXValueCreate(.cfRange, &CFRange(location: newPos, length: 0)) {
                    AXUIElementSetAttributeValue(
                        focusedElement, kAXSelectedTextRangeAttribute as CFString, newRange
                    )
                }
                return true
            }
        }

        // Some fields don't expose kAXValueAttribute but support kAXSelectedTextAttribute insertion
        let insertResult = AXUIElementSetAttributeValue(
            focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        return insertResult == .success
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

    private func isSecureTextField(_ element: AXUIElement) -> Bool {
        var roleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleRef
        ) == .success else { return false }
        return (roleRef as? String) == kAXSecureTextFieldRole as String
    }

    // MARK: - Tier 2: Clipboard + Cmd+V

    private func pasteboardInsert(text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.pasteboardItems?.compactMap { item -> (String, NSData)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data as NSData)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
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
