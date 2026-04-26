import SwiftUI
import AppKit

final class FirstRunWindowController: NSWindowController {
    convenience init(
        transcriptionEngine: TranscriptionEngine,
        mlxModelManager: MLXModelManager,
        whisperModel: String,
        mlxModelID: String,
        onComplete: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to LocalVoice"
        window.center()
        window.contentView = NSHostingView(rootView: FirstRunView(
            transcriptionEngine: transcriptionEngine,
            mlxModelManager: mlxModelManager,
            whisperModel: whisperModel,
            mlxModelID: mlxModelID,
            onComplete: onComplete
        ))
        self.init(window: window)
    }
}

struct FirstRunView: View {
    @ObservedObject var transcriptionEngine: TranscriptionEngine
    @ObservedObject var mlxModelManager: MLXModelManager
    let whisperModel: String
    let mlxModelID: String
    let onComplete: () -> Void

    var whisperProgress: Double { transcriptionEngine.isModelLoaded ? 1.0 : 0.0 }
    var mlxProgress: Double { mlxModelManager.downloadProgress[mlxModelID] ?? 0.0 }
    var isMLXDownloaded: Bool { mlxModelManager.isDownloaded(mlxModelID) }

    var allDone: Bool { transcriptionEngine.isModelLoaded && isMLXDownloaded }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("Welcome to LocalVoice")
                    .font(.title2.bold())
                Text("Setting up your local AI models. This only happens once.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 20) {
                ModelDownloadRow(
                    label: "Whisper — Speech Recognition",
                    sublabel: "openai_whisper-large-v3-turbo · ~400 MB",
                    progress: transcriptionEngine.isModelLoaded ? 1.0 : nil,
                    isComplete: transcriptionEngine.isModelLoaded
                )

                ModelDownloadRow(
                    label: "Qwen3.5 — Text Refinement (LLM)",
                    sublabel: mlxModelDisplayName(mlxModelID),
                    progress: isMLXDownloaded ? 1.0 : (mlxProgress > 0 ? mlxProgress : nil),
                    isComplete: isMLXDownloaded
                )
            }
            .padding(.horizontal)

            if allDone {
                VStack(spacing: 12) {
                    Label("Ready to use", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.headline)
                    Text("Hold Right ⌘ to record. Release to transcribe.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                Text("Downloading… Keep LocalVoice open.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(32)
        .frame(width: 480)
    }

    private func mlxModelDisplayName(_ id: String) -> String {
        let name = id.split(separator: "/").last.map(String.init) ?? id
        let sizeGB: String
        switch id {
        case let s where s.contains("2B"): sizeGB = "~1.6 GB"
        case let s where s.contains("4B"): sizeGB = "~2.9 GB"
        case let s where s.contains("9B"): sizeGB = "~5.0 GB"
        case let s where s.contains("27B"): sizeGB = "~14 GB"
        default: sizeGB = ""
        }
        return "\(name) · \(sizeGB)"
    }
}

private struct ModelDownloadRow: View {
    let label: String
    let sublabel: String
    let progress: Double?
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else if let p = progress, p > 0 {
                    CircularProgress(value: p)
                        .frame(width: 28, height: 28)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Text(sublabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let p = progress, !isComplete {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

private struct CircularProgress: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))%")
                .font(.system(size: 7, weight: .medium))
        }
    }
}
