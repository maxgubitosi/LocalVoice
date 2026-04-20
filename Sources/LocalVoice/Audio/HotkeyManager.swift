import Carbon
import AppKit

/// Monitors Right Command via CGEventTap. Two recording modes:
/// - Hold: press and hold to record, release to transcribe.
/// - Latch: double-tap to start recording hands-free, tap again to stop and transcribe.
final class HotkeyManager {
    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp:   (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var physicalKeyDown = false

    var monitoredKeyCode: CGKeyCode = 0x36 // kVK_RightCommand

    // MARK: - State machine

    private enum State {
        case idle
        case held               // key physically held, recording
        case waitingDoubleTap   // first quick tap released, waiting for second within window
        case latched            // latch mode: recording until next tap
    }

    private var state: State = .idle
    private var keyDownTime: Date = Date()
    private var doubleTapTimer: Timer?

    private let holdThreshold: TimeInterval = 0.25   // shorter = tap, longer = hold
    private let doubleTapWindow: TimeInterval = 0.30  // max gap between the two taps

    init() { setupEventTap() }
    deinit { teardown() }

    // MARK: - Event tap

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
        // macOS deshabilita el tap si tarda demasiado — lo re-habilitamos aquí
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            if physicalKeyDown {
                physicalKeyDown = false
                DispatchQueue.main.async { self.handleKeyUp() }
            }
            return nil
        }

        if type == .flagsChanged {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == monitoredKeyCode else {
                return Unmanaged.passUnretained(event)
            }
            let isDown = event.flags.contains(.maskCommand)
            if isDown && !physicalKeyDown {
                physicalKeyDown = true
                DispatchQueue.main.async { self.handleKeyDown() }
                return nil
            } else if !isDown && physicalKeyDown {
                physicalKeyDown = false
                DispatchQueue.main.async { self.handleKeyUp() }
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - State transitions (always called on main thread)

    private func handleKeyDown() {
        switch state {
        case .idle:
            state = .held
            keyDownTime = Date()
            onHotkeyDown?()  // start recording immediately

        case .waitingDoubleTap:
            // Second tap confirmed — enter latch mode
            // Recording is already running from the first tap, no need to restart
            doubleTapTimer?.invalidate()
            doubleTapTimer = nil
            state = .latched

        case .latched:
            // Tap while latched — stop and transcribe
            state = .idle
            onHotkeyUp?()

        case .held:
            break
        }
    }

    private func handleKeyUp() {
        switch state {
        case .held:
            let duration = Date().timeIntervalSince(keyDownTime)
            if duration < holdThreshold {
                // Quick tap — wait to see if a second tap follows
                state = .waitingDoubleTap
                doubleTapTimer = Timer.scheduledTimer(withTimeInterval: doubleTapWindow, repeats: false) { [weak self] _ in
                    guard let self, self.state == .waitingDoubleTap else { return }
                    // No second tap arrived — treat as a short hold: stop and transcribe
                    self.state = .idle
                    self.onHotkeyUp?()
                }
            } else {
                // Long hold released — stop and transcribe
                state = .idle
                onHotkeyUp?()
            }

        case .latched:
            break  // key-up ignored in latch mode

        case .idle, .waitingDoubleTap:
            break
        }
    }

    private func teardown() {
        doubleTapTimer?.invalidate()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
