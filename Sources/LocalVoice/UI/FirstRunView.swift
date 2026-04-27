import SwiftUI
import AppKit
import Combine

final class FirstRunWindowController: NSWindowController {
    convenience init(
        transcriptionEngine: TranscriptionEngine,
        mlxModelManager: MLXModelManager,
        whisperModel: String,
        mlxModelID: String,
        onComplete: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 600),
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

    @State private var permissions = PermissionManager.current()
    private let permissionsRefreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var mlxProgress: Double { mlxModelManager.downloadProgress[mlxModelID] ?? 0.0 }
    var isMLXDownloaded: Bool { mlxModelManager.isDownloaded(mlxModelID) }
    var allDone: Bool { transcriptionEngine.isModelLoaded && isMLXDownloaded }
    var readyToFinish: Bool { allDone && permissions.allGranted }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LVPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            setupStepHeader(
                                title: "Local models",
                                subtitle: "Whisper handles speech recognition. MLX handles optional refinement. Both run on this Mac."
                            )

                            ModelDownloadRow(
                                label: "Whisper speech recognition",
                                sublabel: "\(TranscriptionEngine.displayName(for: whisperModel)) · stored locally",
                                progress: transcriptionEngine.isModelLoaded ? 1.0 : nil,
                                isComplete: transcriptionEngine.isModelLoaded
                            )

                            ModelDownloadRow(
                                label: "Qwen text refinement",
                                sublabel: mlxModelDisplayName(mlxModelID),
                                progress: isMLXDownloaded ? 1.0 : (mlxProgress > 0 ? mlxProgress : nil),
                                isComplete: isMLXDownloaded
                            )
                        }
                    }

                    LVPanel {
                        PermissionsChecklistView()
                    }

                    LVPanel {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(LVStyle.accent)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(LVStyle.accent.opacity(0.12))
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hardware-aware default")
                                    .font(.headline)
                                Text("\(DeviceCapability.chipGeneration) · \(DeviceCapability.physicalMemoryGB) GB RAM · \(DeviceCapability.recommendedMLXModelLabel)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            footer
        }
        .background(LVStyle.background)
        .frame(width: 640, height: 600)
        .onAppear { permissions = PermissionManager.current() }
        .onReceive(permissionsRefreshTimer) { _ in permissions = PermissionManager.current() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 5) {
                Text("Welcome to LocalVoice")
                    .font(.title2.weight(.semibold))
                Text("Private voice dictation for Mac. The first launch prepares models and permissions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(24)
        .background(LVStyle.groupedBackground.opacity(0.65))
    }

    private var footer: some View {
        HStack {
            if readyToFinish {
                Label("Ready to use", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(LVStyle.ready)
                    .font(.headline)
            } else if allDone {
                Label("Grant the remaining permissions to continue", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(LVStyle.warning)
                    .font(.headline)
            } else {
                Label("Preparing local models", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .font(.headline)
            }

            Spacer()

            Button("Get Started") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!readyToFinish)
        }
        .padding(18)
        .background(LVStyle.groupedBackground.opacity(0.65))
    }

    private func setupStepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mlxModelDisplayName(_ id: String) -> String {
        let name = id.split(separator: "/").last.map(String.init) ?? id
        let sizeGB: String
        switch id {
        case let s where s.contains("2B"): sizeGB = "~1.6 GB"
        case let s where s.contains("4B"): sizeGB = "~2.9 GB"
        case let s where s.contains("9B"): sizeGB = "~5.0 GB"
        case let s where s.contains("27B"): sizeGB = "~14 GB"
        default: sizeGB = "local download"
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
        HStack(spacing: 12) {
            ZStack {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LVStyle.ready)
                        .font(.system(size: 22, weight: .semibold))
                } else if let progress, progress > 0 {
                    CircularProgress(value: progress)
                        .frame(width: 28, height: 28)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    LVBadge(isComplete ? "Ready" : "Downloading", tint: isComplete ? LVStyle.ready : LVStyle.warning)
                }
                Text(sublabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress, !isComplete {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(LVStyle.accent)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LVStyle.groupedBackground.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(LVStyle.separator, lineWidth: 0.5)
        )
    }
}

private struct CircularProgress: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(LVStyle.separator, lineWidth: 3)
            Circle()
                .trim(from: 0, to: value)
                .stroke(LVStyle.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(value * 100))")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
