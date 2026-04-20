import AppKit
import SwiftUI

enum OverlayState {
    case recording
    case transcribing
    case refining(transcript: String)
    case error(String)
}

final class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .recording
}

private let overlayWindowSize = CGSize(width: 320, height: 96)

final class RecordingOverlayWindow: NSWindow {
    private let viewModel = OverlayViewModel()

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - overlayWindowSize.width - 16,
            y: screen.visibleFrame.minY + 16
        )

        super.init(
            contentRect: CGRect(origin: origin, size: overlayWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: RecordingOverlayView(viewModel: viewModel))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = CGRect(origin: .zero, size: overlayWindowSize)
        contentView = hosting
    }

    func show(state: OverlayState) {
        viewModel.state = state
        if !isVisible {
            alphaValue = 0
            orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                animator().alphaValue = 1
            }
        }
    }

    func showTranscribing() { show(state: .transcribing) }

    func showRefining(transcript: String) { show(state: .refining(transcript: transcript)) }

    func showError(_ message: String) {
        show(state: .error(message))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.hide() }
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

// MARK: - SwiftUI root

struct RecordingOverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    private var stateID: Int {
        switch viewModel.state {
        case .recording:    return 0
        case .transcribing: return 1
        case .refining:     return 2
        case .error:        return 3
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            stateView
                .animation(.easeInOut(duration: 0.18), value: stateID)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .frame(width: overlayWindowSize.width, height: overlayWindowSize.height)
    }

    @ViewBuilder
    private var stateView: some View {
        switch viewModel.state {
        case .recording:
            RecordingContent()
        case .transcribing:
            SpinnerContent(label: "Transcribiendo…", tint: .white)
        case .refining(let transcript):
            RefiningContent(transcript: transcript)
        case .error(let message):
            ErrorContent(message: message)
        }
    }
}

// MARK: - State views

private struct RecordingContent: View {
    @State private var pulsing = false
    @State private var bars: [CGFloat] = Array(repeating: 0.3, count: 8)
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulsing ? 1.5 : 1.0)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
            }

            HStack(spacing: 2.5) {
                ForEach(bars.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 3, height: bars[i] * 26 + 4)
                        .animation(.easeInOut(duration: 0.1), value: bars[i])
                }
            }
            .frame(height: 34)
        }
        .pillStyle()
        .onAppear { pulsing = true }
        .onReceive(timer) { _ in bars = bars.map { _ in CGFloat.random(in: 0.1...1.0) } }
    }
}

private struct SpinnerContent: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.75)
                .tint(tint)
                .frame(width: 18, height: 18)

            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .pillStyle()
    }
}

private struct RefiningContent: View {
    let transcript: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.75)
                .tint(Color(red: 0.45, green: 0.75, blue: 1.0))
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text("Mejorando…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(transcript)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 230, alignment: .leading)
            }
        }
        .pillStyle()
    }
}

private struct ErrorContent: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))

            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(maxWidth: 220, alignment: .leading)
        }
        .pillStyle(background: Color(red: 0.35, green: 0.07, blue: 0.0).opacity(0.95))
    }
}

// MARK: - Shared pill style

private struct PillModifier: ViewModifier {
    var background: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(background)
                    .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: 5)
            )
    }
}

private extension View {
    func pillStyle(background: Color = Color(white: 0.1, opacity: 0.92)) -> some View {
        modifier(PillModifier(background: background))
    }
}
