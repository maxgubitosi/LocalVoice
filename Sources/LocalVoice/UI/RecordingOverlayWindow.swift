import AppKit
import SwiftUI

enum OverlayState {
    case recording
    case processing
    case error(String)
}

final class OverlayViewModel: ObservableObject {
    @Published var state: OverlayState = .recording
}

final class RecordingOverlayWindow: NSWindow {
    private let viewModel = OverlayViewModel()

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

        let view = RecordingOverlayView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: windowSize)
        contentView = hosting
    }

    func show(state: OverlayState = .recording) {
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

    func showProcessing() {
        show(state: .processing)
    }

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

// MARK: - SwiftUI View

struct RecordingOverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .recording:
                RecordingContent()
            case .processing:
                ProcessingContent()
            case .error(let message):
                ErrorContent(message: message)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundFill)
        )
        .frame(width: 220, height: 64)
    }

    private var backgroundFill: Color {
        switch viewModel.state {
        case .error: return Color(red: 0.5, green: 0.1, blue: 0.0).opacity(0.92)
        default:     return Color.black.opacity(0.82)
        }
    }
}

private struct RecordingContent: View {
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
        .onAppear { pulsing = true }
        .onReceive(timer) { _ in bars = bars.map { _ in CGFloat.random(in: 0.1...1.0) } }
    }
}

private struct ProcessingContent: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .tint(.white)

            Text("Transcribiendo…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
        }
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
        }
    }
}
