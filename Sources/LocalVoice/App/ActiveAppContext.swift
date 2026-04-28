import AppKit
import ApplicationServices
import Foundation

struct ActiveAppContext {
    let bundleID: String?
    let name: String
    let browserPage: BrowserPageContext?

    var promptDescription: String {
        guard let pageDescription = browserPage?.promptDescription else { return name }
        return "\(name) - active page: \(pageDescription)"
    }

    static func captureFrontmost() -> ActiveAppContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleID = app.bundleIdentifier
        let name = app.localizedName ?? "Unknown"
        return ActiveAppContext(
            bundleID: bundleID,
            name: name,
            browserPage: BrowserPageContext.capture(for: app)
        )
    }
}

struct BrowserPageContext {
    let title: String?
    let url: String?

    init(title: String?, url: String?) {
        self.title = Self.cleaned(title)

        if let rawURL = Self.cleaned(url),
           let parsedURL = URL(string: rawURL),
           let sanitizedURL = Self.sanitized(parsedURL) {
            self.url = sanitizedURL
        } else {
            self.url = Self.cleaned(url)
        }
    }

    var promptDescription: String? {
        switch (title, url) {
        case let (title?, url?) where title != url:
            return "\(title) (\(url))"
        case let (title?, _):
            return title
        case let (_, url?):
            return url
        default:
            return nil
        }
    }

    static func capture(for app: NSRunningApplication) -> BrowserPageContext? {
        guard browserBundleIDs.contains(app.bundleIdentifier ?? ""),
              AXIsProcessTrusted()
        else { return nil }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = focusedWindow(in: appElement) else { return nil }

        let windowTitle = stringAttribute(window, kAXTitleAttribute)
        let windowURL = urlAttribute(window, kAXURLAttribute)
            ?? urlAttribute(window, kAXDocumentAttribute)

        if let webArea = findWebArea(in: window) {
            let title = stringAttribute(webArea, kAXTitleAttribute) ?? windowTitle
            let url = urlAttribute(webArea, kAXURLAttribute)
                ?? urlAttribute(webArea, kAXDocumentAttribute)
                ?? windowURL
            let page = BrowserPageContext(title: title, url: url)
            return page.promptDescription == nil ? nil : page
        }

        let page = BrowserPageContext(title: windowTitle, url: windowURL)
        return page.promptDescription == nil ? nil : page
    }

    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.dev",
        "com.brave.Browser.nightly",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
        "com.google.Chrome.forTesting",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary",
        "com.microsoft.edgemac.Dev",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
        "company.thebrowser.Browser.beta",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly"
    ]

    private static func focusedWindow(in appElement: AXUIElement) -> AXUIElement? {
        var windowRef: AnyObject?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success, let windowRef {
            return (windowRef as! AXUIElement)
        }

        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsRef
        ) == .success,
              let windows = windowsRef as? [AnyObject],
              let firstWindow = windows.first
        else { return nil }

        return (firstWindow as! AXUIElement)
    }

    private static func findWebArea(in root: AXUIElement) -> AXUIElement? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0
        var visited = 0

        while index < queue.count, visited < 180 {
            let item = queue[index]
            index += 1
            visited += 1

            let role = stringAttribute(item.element, kAXRoleAttribute)
            if role == "AXWebArea" { return item.element }
            guard item.depth < 7 else { continue }

            for child in children(of: item.element) {
                queue.append((child, item.depth + 1))
            }
        }

        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success,
              let children = childrenRef as? [AnyObject]
        else { return [] }

        return children.map { ($0 as! AXUIElement) }
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return cleaned(ref as? String)
    }

    private static func urlAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }

        if let url = ref as? URL {
            return sanitized(url)
        }

        guard let raw = cleaned(ref as? String) else { return nil }
        if let url = URL(string: raw), let sanitized = sanitized(url) {
            return sanitized
        }
        return raw
    }

    private static func sanitized(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return cleaned(url.absoluteString)
        }
        components.query = nil
        components.fragment = nil
        return cleaned(components.string)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
