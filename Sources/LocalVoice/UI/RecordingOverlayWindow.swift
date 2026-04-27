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

private let overlayWindowSize = CGSize(width: 220, height: 76)

final class RecordingOverlayWindow: NSWindow {
    private let viewModel = OverlayViewModel()

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = CGPoint(
            x: screen.visibleFrame.maxX - overlayWindowSize.width - 18,
            y: screen.visibleFrame.minY + 18
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
                ctx.duration = 0.18
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
            ctx.duration = 0.14
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
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
                .animation(.easeInOut(duration: 0.16), value: stateID)
                .padding(.trailing, 18)
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
            ProcessingContent(title: "Transcribing...", subtitle: nil, tint: .white)
        case .refining(let transcript):
            ProcessingContent(title: "Refining...", subtitle: transcript, tint: Color(red: 0.48, green: 0.74, blue: 1.0))
        case .error(let message):
            ErrorContent(message: message)
        }
    }
}

private struct RecordingContent: View {
    @State private var pulsing = false
    @State private var bars: [CGFloat] = Array(repeating: 0.35, count: 9)
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.28))
                    .frame(width: 20, height: 20)
                    .scaleEffect(pulsing ? 1.42 : 1.0)
                    .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: pulsing)
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 22, height: 22)

            Text("Recording")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            WaveformBars(bars: bars)
        }
        .overlayPill()
        .onAppear { pulsing = true }
        .onReceive(timer) { _ in bars = bars.map { _ in CGFloat.random(in: 0.18...1.0) } }
    }
}

private struct ProcessingContent: View {
    let title: String
    let subtitle: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.72)
                .tint(tint)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 150, alignment: .leading)
                }
            }
        }
        .overlayPill()
    }
}

private struct ErrorContent: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22, height: 22)

            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: 150, alignment: .leading)
        }
        .overlayPill(background: Color(red: 0.30, green: 0.08, blue: 0.05).opacity(0.96))
    }
}

private struct WaveformBars: View {
    let bars: [CGFloat]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(bars.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.82))
                    .frame(width: 3, height: bars[index] * 18 + 4)
                    .animation(.easeInOut(duration: 0.10), value: bars[index])
            }
        }
        .frame(width: 44, height: 26)
    }
}

private struct OverlayPillModifier: ViewModifier {
    var background: Color

    func body(content: Content) -> some View {
        content
            .frame(minWidth: 148, minHeight: 40)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(background)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.24), radius: 14, x: 0, y: 8)
    }
}

private extension View {
    func overlayPill(background: Color = Color(white: 0.08).opacity(0.88)) -> some View {
        modifier(OverlayPillModifier(background: background))
    }
}
