import SwiftUI
import AppKit

final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings, promptStore: PromptStore, mlxModelManager: MLXModelManager, transcriptionEngine: TranscriptionEngine) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 660),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LocalVoice Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(
            settings: settings,
            promptStore: promptStore,
            mlxModelManager: mlxModelManager,
            transcriptionEngine: transcriptionEngine
        ))
        self.init(window: window)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var promptStore: PromptStore
    @ObservedObject var mlxModelManager: MLXModelManager
    let transcriptionEngine: TranscriptionEngine
    @State private var showingPromptManager = false

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(AppMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Transcription (Whisper)") {
                ForEach(TranscriptionEngine.availableModels, id: \.self) { model in
                    WhisperModelRow(
                        model: model,
                        isSelected: settings.whisperModel == model,
                        isDownloaded: transcriptionEngine.isModelDownloaded(model),
                        onSelect: { settings.whisperModel = model }
                    )
                }

                Picker("Language", selection: $settings.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                Text("System uses your macOS language. Auto may default to English for short clips.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("LLM Model (Refine Mode)") {
                ForEach(MLXModelCatalog.models) { model in
                    MLXModelRow(
                        model: model,
                        isSelected: settings.llmModel == model.id,
                        isRecommended: model.id == MLXModelCatalog.recommendedModelID,
                        isDownloaded: mlxModelManager.downloadedModels.contains(model.id),
                        progress: mlxModelManager.downloadProgress[model.id],
                        onSelect: { settings.llmModel = model.id },
                        onDownload: {
                            Task { try? await mlxModelManager.downloadModel(model.id) }
                        },
                        onDelete: { try? mlxModelManager.deleteModel(model.id) }
                    )
                }
            }

            Section("LLM Prompt") {
                Picker("Active Prompt", selection: $settings.activePromptID) {
                    ForEach(promptStore.prompts) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                Button("Manage Prompts…") { showingPromptManager = true }
                Text("Hold Right ⌘ + number key to temporarily use a different prompt.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .sheet(isPresented: $showingPromptManager) {
                PromptsManagementView(promptStore: promptStore, settings: settings)
                    .frame(minWidth: 560, minHeight: 400)
            }

            Section("Privacy") {
                Toggle("Save transcribed text in history", isOn: $settings.saveTranscribedText)
                Text("Text is stored locally only, never sent to any server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Permissions") {
                PermissionsChecklistView()
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 440)
    }
}

// MARK: - Whisper model row

private struct WhisperModelRow: View {
    let model: String
    let isSelected: Bool
    let isDownloaded: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack(spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                    Text(TranscriptionEngine.displayName(for: model))
                        .foregroundColor(.primary)
                    Spacer()
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - MLX model row

private struct MLXModelRow: View {
    let model: MLXModelInfo
    let isSelected: Bool
    let isRecommended: Bool
    let isDownloaded: Bool
    let progress: Double?
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var isDownloading: Bool { progress != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: { if isDownloaded { onSelect() } }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .accentColor : (isDownloaded ? .secondary : Color(nsColor: .tertiaryLabelColor)))
                }
                .buttonStyle(.plain)
                .disabled(!isDownloaded)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .fontWeight(isSelected ? .semibold : .regular)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    Text("\(model.speedLabel) · \(model.paramCount) · \(String(format: "%.1f", model.estimatedRAMGB)) GB RAM · \(String(format: "%.1f", model.downloadSizeGB)) GB download")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isDownloading {
                    // no action button while downloading
                } else if isDownloaded {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete model")
                } else {
                    Button(action: onDownload) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }

            if let p = progress {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
    }
}
