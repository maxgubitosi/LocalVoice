import AppKit
import QuartzCore
import SwiftUI

enum OverlayState {
    case recording
    case transcribing
    case refining(promptName: String, transcript: String)
    case error(String)
}

extension OverlayState {
    var displayTitle: String {
        switch self {
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing..."
        case .refining(let promptName, _):
            return "\(promptName)..."
        case .error(let message):
            return message
        }
    }
}

final class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .recording
}

private let overlayWindowSize = CGSize(width: 184, height: 54)
private let overlayWindowPadding: CGFloat = 10

final class RecordingOverlayWindow: NSPanel {
    private let viewModel = OverlayViewModel()
    private var presentationGeneration = 0

    init() {
        super.init(
            contentRect: Self.frameForCurrentScreen(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: RecordingOverlayView(viewModel: viewModel))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = CGRect(origin: .zero, size: overlayWindowSize)
        contentView = hosting

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenLayoutChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func show(state: OverlayState) {
        presentationGeneration += 1
        viewModel.state = state
        setFrame(Self.frameForCurrentScreen(), display: true)
        contentView?.needsDisplay = true

        if !isVisible {
            alphaValue = 0
        }
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func showTranscribing() { show(state: .transcribing) }

    func showRefining(promptName: String, transcript: String) {
        show(state: .refining(promptName: promptName, transcript: transcript))
    }

    func showError(_ message: String) {
        show(state: .error(message))
        let generation = presentationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            if case .error = self.viewModel.state {
                self.hide()
            }
        }
    }

    func hide() {
        presentationGeneration += 1
        let generation = presentationGeneration
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            guard self.presentationGeneration == generation else { return }
            self.orderOut(nil)
        })
    }

    @objc private func screenLayoutChanged() {
        guard isVisible else { return }
        setFrame(Self.frameForCurrentScreen(), display: true, animate: false)
    }

    private static func frameForCurrentScreen() -> CGRect {
        let screen = screenForOverlay()
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.maxX - overlayWindowSize.width - overlayWindowPadding,
            y: visibleFrame.minY + overlayWindowPadding
        )
        return CGRect(origin: origin, size: overlayWindowSize)
    }

    private static func screenForOverlay() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    private var stateID: Int {
        switch viewModel.state {
        case .recording: return 0
        case .transcribing: return 1
        case .refining: return 2
        case .error: return 3
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            stateView
                .id(stateID)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
                .animation(.easeInOut(duration: 0.16), value: stateID)
                .padding(.trailing, overlayWindowPadding)
                .padding(.bottom, overlayWindowPadding)
        }
        .frame(width: overlayWindowSize.width, height: overlayWindowSize.height)
    }

    @ViewBuilder
    private var stateView: some View {
        switch viewModel.state {
        case .recording:
            RecordingContent()
        case .transcribing:
            ProcessingContent(title: "Transcribing")
        case .refining(let promptName, _):
            ProcessingContent(title: promptName)
        case .error(let message):
            ErrorContent(message: message)
        }
    }
}

private struct RecordingContent: View {
    var body: some View {
        HStack(spacing: 10) {
            RecordingGlyph()

            TimelineView(.animation(minimumInterval: 1.0 / 18.0)) { timeline in
                WaveformBars(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .overlayPill(horizontalPadding: 14)
    }
}

private struct ProcessingContent: View {
    let title: String

    var body: some View {
        ShimmerText(title)
        .overlayPill()
    }
}

private struct ErrorContent: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .frame(maxWidth: 116, alignment: .leading)
        }
        .overlayPill(background: Color.black.opacity(0.62))
    }
}

private struct WaveformBars: View {
    let time: TimeInterval

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.58))
                    .frame(width: 3, height: barHeight(at: index))
            }
        }
        .frame(width: 34, height: 20)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let phase = time * 5.0 + Double(index) * 0.82
        let normalized = (sin(phase) + 1) / 2
        return CGFloat(4 + normalized * 12)
    }
}

private struct RecordingGlyph: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = (sin(time * 3.8) + 1) / 2

            ZStack {
                Circle()
                    .fill(Color(nsColor: .systemRed).opacity(0.10 + 0.10 * pulse))
                    .frame(width: 18, height: 18)
                    .scaleEffect(1.0 + 0.18 * pulse)
                Circle()
                    .fill(Color(nsColor: .systemRed))
                    .frame(width: 6, height: 6)
            }
            .frame(width: 20, height: 20)
        }
    }
}

private struct ShimmerText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let progress = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.35) / 1.35

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.50), location: 0.0),
                            .init(color: .white.opacity(0.96), location: 0.48),
                            .init(color: .white.opacity(0.50), location: 1.0),
                        ],
                        startPoint: UnitPoint(x: progress * 2 - 1.0, y: 0.5),
                        endPoint: UnitPoint(x: progress * 2, y: 0.5)
                    )
                )
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct OverlayPillModifier: ViewModifier {
    var background: Color
    var horizontalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: 62, minHeight: 26)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 4)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(background)
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.13), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 5)
    }
}

private extension View {
    func overlayPill(
        background: Color = Color.black.opacity(0.56),
        horizontalPadding: CGFloat = 10
    ) -> some View {
        modifier(OverlayPillModifier(background: background, horizontalPadding: horizontalPadding))
    }
}
