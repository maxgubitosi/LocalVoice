import AppKit
import SwiftUI

/// Floating, always-on-top overlay shown while recording.
/// Displays a pulsing waveform animation in the bottom-right corner.
final class RecordingOverlayWindow: NSWindow {
    private var hostingView: NSHostingView<RecordingOverlayView>?

    init() {
        let windowSize = CGSize(width: 220, height: 64)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let frame = CGRect(
            x: screen.visibleFrame.maxX - windowSize.width - 24,
            y: screen.visibleFrame.minY + 24,
            width: windowSize.width,
            height: windowSize.height
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = RecordingOverlayView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: windowSize)
        contentView = hosting
        hostingView = hosting
    }

    func show() {
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 1
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

// MARK: - SwiftUI View

struct RecordingOverlayView: View {
    @State private var pulsing = false
    @State private var bars: [CGFloat] = Array(repeating: 0.3, count: 12)
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(), value: pulsing)

            HStack(spacing: 3) {
                ForEach(bars.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 3, height: bars[i] * 36 + 6)
                        .animation(.easeInOut(duration: 0.1), value: bars[i])
                }
            }
            .frame(height: 40)

            Text("Recording…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.82))
        )
        .onAppear { pulsing = true }
        .onReceive(timer) { _ in animateBars() }
    }

    private func animateBars() {
        bars = bars.map { _ in CGFloat.random(in: 0.1...1.0) }
    }
}
