import Carbon
import AppKit

/// Monitors a global hotkey using CGEventTap (requires Input Monitoring permission).
/// Default: right Option key (kVK_RightOption). Hold to record, release to stop.
final class HotkeyManager {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp:   (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHeld = false

    // The key to monitor — right Option by default, easily changed via Settings
    var monitoredKeyCode: CGKeyCode = 0x3D // kVK_RightOption

    init() { setupEventTap() }

    deinit { teardown() }

    private func setupEventTap() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)   |
            (1 << CGEventType.flagsChanged.rawValue)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            print("[HotkeyManager] Failed to create event tap. Check Input Monitoring permission.")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // flagsChanged fires for modifier-only keys (Option, Command, etc.)
        if type == .flagsChanged {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == monitoredKeyCode else {
                return Unmanaged.passUnretained(event)
            }
            let flags = event.flags
            let isDown = flags.contains(.maskAlternate) // Option key pressed
            if isDown && !isHeld {
                isHeld = true
                onHotkeyDown?()
                return nil // Consume the event so it doesn't reach other apps
            } else if !isDown && isHeld {
                isHeld = false
                onHotkeyUp?()
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func teardown() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
