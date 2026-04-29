import SwiftUI
import AppKit

final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings, promptStore: PromptStore, mlxModelManager: MLXModelManager, transcriptionEngine: TranscriptionEngine) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 660),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LocalVoice Settings"
        window.center()
        window.minSize = CGSize(width: 760, height: 560)
        window.contentView = NSHostingView(rootView: SettingsView(
            settings: settings,
            promptStore: promptStore,
            mlxModelManager: mlxModelManager,
            transcriptionEngine: transcriptionEngine
        ))
        self.init(window: window)
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case transcription = "Transcription"
    case refine = "Refine"
    case prompts = "Prompts"
    case privacy = "Privacy & Permissions"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .overview: return "gauge.medium"
        case .transcription: return "waveform"
        case .refine: return "wand.and.stars"
        case .prompts: return "text.badge.plus"
        case .privacy: return "lock.shield"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var promptStore: PromptStore
    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var transcriptionEngine: TranscriptionEngine

    @State private var selectedPage: SettingsPage = .overview
    @State private var showingPromptManager = false
    @State private var permissions = PermissionManager.current()

    private let permissionsRefreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(LVStyle.groupedBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LVStyle.background)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            permissions = PermissionManager.current()
            mlxModelManager.refreshDownloadedModels()
        }
        .onReceive(permissionsRefreshTimer) { _ in
            permissions = PermissionManager.current()
        }
        .sheet(isPresented: $showingPromptManager) {
            PromptsManagementView(promptStore: promptStore, settings: settings)
                .frame(minWidth: 680, minHeight: 480)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("LocalVoice")
                        .font(.headline)
                    Text("Private dictation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    SettingsSidebarRow(
                        page: page,
                        isSelected: selectedPage == page,
                        action: { selectedPage = page }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            LVPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        LVStatusDot(color: permissions.allGranted ? LVStyle.ready : LVStyle.warning)
                        Text(permissions.allGranted ? "Ready" : "Needs setup")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("Hold \(settings.recordingHotkey.label) to record in any focused text field.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedPage {
        case .overview:
            overviewPage
        case .transcription:
            transcriptionPage
        case .refine:
            refinePage
        case .prompts:
            promptsPage
        case .privacy:
            privacyPage
        }
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LVSectionHeader(
                "Overview",
                subtitle: "A quick read on your dictation setup, local models, and current workflow."
            )

            LVPanel {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: overviewStatus.symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(overviewStatus.color)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(overviewStatus.color.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(overviewStatus.title)
                            .font(.title3.weight(.semibold))
                        Text(overviewStatus.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                LVPanel { LVMetric(label: "Mode", value: settings.mode.rawValue, systemImage: modeSymbol, tint: modeTint) }
                LVPanel { LVMetric(label: "Language", value: settings.transcriptionLanguage.displayName, systemImage: "globe", tint: .cyan) }
                LVPanel { LVMetric(label: "Prompt", value: activePrompt.name, systemImage: "text.badge.checkmark", tint: .purple) }
                LVPanel { LVMetric(label: overviewWhisperModelName, value: "Whisper", systemImage: "waveform", tint: transcriptionEngine.isModelLoaded ? LVStyle.ready : LVStyle.warning) }
                LVPanel { LVMetric(label: "Refine model", value: selectedMLXModel?.displayName ?? "Selected", systemImage: "memorychip", tint: isSelectedMLXDownloaded ? LVStyle.ready : LVStyle.warning) }
                LVPanel { LVMetric(label: "Permissions", value: permissions.allGranted ? "Granted" : "Missing", systemImage: "lock.shield", tint: permissions.allGranted ? LVStyle.ready : LVStyle.warning) }
            }

            LVPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recording workflow")
                            .font(.headline)
                        Spacer()
                        LVBadge(settings.recordingHotkey.label, systemImage: settings.recordingHotkey.systemImage, tint: LVStyle.accent)
                    }
                    HStack(spacing: 8) {
                        LVKeyCap("Hold")
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text("speak")
                            .font(.subheadline)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        LVKeyCap("Release")
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Text("text appears")
                            .font(.subheadline.weight(.medium))
                    }
                    Text("Double-tap \(settings.recordingHotkey.label) to latch recording. While recording, press 1-9 to temporarily switch prompts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transcriptionPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LVSectionHeader(
                "Transcription",
                subtitle: "Choose how LocalVoice turns speech into text before it reaches the active app."
            )

            LVPanel {
                VStack(alignment: .leading, spacing: 14) {
                    settingLabel("Mode")
                    Picker("Mode", selection: $settings.mode) {
                        ForEach(AppMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Divider()

                    settingLabel("Language")
                    Picker("Language", selection: $settings.transcriptionLanguage) {
                        ForEach(TranscriptionLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("For Spanish dictation, choose Spanish directly. Auto may misdetect short Spanish clips and Refine can then answer in English.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LVPanel {
                VStack(alignment: .leading, spacing: 12) {
                    settingLabel("Recording hotkey")
                    Picker("Recording Hotkey", selection: $settings.recordingHotkey) {
                        ForEach(RecordingHotkey.allCases) { hotkey in
                            Text(hotkey.label).tag(hotkey)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Prompt shortcuts stay simple: while recording, press 1-9 to temporarily switch prompts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LVPanel {
                VStack(alignment: .leading, spacing: 12) {
                    settingLabel("Whisper model")
                    ForEach(TranscriptionEngine.availableModels, id: \.self) { model in
                        WhisperModelRow(
                            model: model,
                            isSelected: settings.whisperModel == model,
                            isDownloaded: transcriptionEngine.isModelDownloaded(model),
                            isLoaded: settings.whisperModel == model && transcriptionEngine.isModelLoaded,
                            onSelect: { settings.whisperModel = model }
                        )
                    }
                }
            }
        }
    }

    private var refinePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LVSectionHeader(
                "Refine",
                subtitle: "Run a local MLX model after transcription to clean up, format, or rewrite dictated text."
            )

            LVPanel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recommended for this Mac")
                                .font(.headline)
                            Text(DeviceCapability.recommendedMLXModelLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        LVBadge("\(DeviceCapability.chipGeneration) · \(DeviceCapability.physicalMemoryGB) GB RAM", systemImage: "desktopcomputer", tint: LVStyle.accent)
                    }
                }
            }

            LVPanel {
                VStack(alignment: .leading, spacing: 12) {
                    settingLabel("Active prompt")
                    Picker("Active Prompt", selection: $settings.activePromptID) {
                        ForEach(promptStore.prompts) { prompt in
                            Text(prompt.name).tag(Optional(prompt.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        showingPromptManager = true
                    } label: {
                        Label("Open Prompt Editor", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)

                    Text("While recording, press a number key to temporarily use that prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LVPanel {
                VStack(alignment: .leading, spacing: 12) {
                    settingLabel("MLX model")
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
            }
        }
    }

    private var promptsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LVSectionHeader(
                "Prompts",
                subtitle: "Use presets for quick rewriting, or create your own number shortcuts for active recordings."
            )

            LVPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        settingLabel("Library")
                        Spacer()
                        Button {
                            showingPromptManager = true
                        } label: {
                            Label("Edit Prompts", systemImage: "pencil")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    ForEach(promptStore.prompts) { prompt in
                        PromptSummaryRow(
                            prompt: prompt,
                            isActive: settings.activePromptID == prompt.id || (settings.activePromptID == nil && prompt.id == LLMPrompt.presetImprove.id),
                            isModified: promptStore.isModified(prompt),
                            onActivate: { settings.activePromptID = prompt.id }
                        )
                    }
                }
            }
        }
    }

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            LVSectionHeader(
                "Privacy & Permissions",
                subtitle: "LocalVoice needs macOS permissions to listen for the hotkey, capture the microphone, and insert text."
            )

            LVPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Save transcribed text in local history", isOn: $settings.saveTranscribedText)
                    Text("When disabled, history keeps metadata and statistics, but not the transcript content.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Include active browser page context", isOn: $settings.includeBrowserPageContext)
                    Text("When enabled, LocalVoice may use the active browser page title and sanitized URL for Refine and local history. Query strings and fragments are removed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LVPanel {
                PermissionsChecklistView()
            }

            LVPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(LVStyle.ready)
                        Text("Privacy model")
                            .font(.headline)
                    }
                    Text("Audio, transcripts, prompts, model inference, and optional browser page context stay on this Mac. LocalVoice uses direct text insertion first and refuses secure password fields.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var activePrompt: LLMPrompt {
        promptStore.activePrompt(id: settings.activePromptID)
    }

    private var selectedMLXModel: MLXModelInfo? {
        MLXModelCatalog.models.first { $0.id == settings.llmModel }
    }

    private var overviewWhisperModelName: String {
        switch settings.whisperModel {
        case "openai_whisper-large-v3_turbo": return "Large V3 Turbo"
        case "large-v3": return "Large V3"
        default:
            return TranscriptionEngine.displayName(for: settings.whisperModel)
                .split(separator: "-")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    private var isSelectedMLXDownloaded: Bool {
        mlxModelManager.downloadedModels.contains(settings.llmModel)
    }

    private var overviewStatus: (title: String, message: String, symbol: String, color: Color) {
        if !permissions.allGranted {
            return (
                "Finish macOS permissions",
                "Microphone, Accessibility, and Input Monitoring must be granted before the hotkey can work reliably.",
                "exclamationmark.triangle.fill",
                LVStyle.warning
            )
        }
        if !transcriptionEngine.isModelLoaded {
            return (
                "Whisper is loading",
                "Direct transcription will be ready as soon as the selected Whisper model finishes loading.",
                "arrow.triangle.2.circlepath",
                LVStyle.warning
            )
        }
        if settings.mode == .llmRewrite && !isSelectedMLXDownloaded {
            return (
                "Refine model not downloaded",
                "Direct transcription is ready. Download the selected MLX model to use Refine mode.",
                "arrow.down.circle.fill",
                LVStyle.warning
            )
        }
        return (
            "Ready for local dictation",
            "Hold \(settings.recordingHotkey.label), speak, and release. LocalVoice will insert the result into the active app.",
            "checkmark.circle.fill",
            LVStyle.ready
        )
    }

    private var modeSymbol: String {
        settings.mode == .llmRewrite ? "wand.and.stars" : "text.cursor"
    }

    private var modeTint: Color {
        settings.mode == .llmRewrite ? .purple : LVStyle.accent
    }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
    }
}

private struct SettingsSidebarRow: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(page.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WhisperModelRow: View {
    let model: String
    let isSelected: Bool
    let isDownloaded: Bool
    let isLoaded: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? LVStyle.accent : LVStyle.tertiaryText)
                    .font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 3) {
                    Text(TranscriptionEngine.displayName(for: model))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(whisperModelDetail(model))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isLoaded {
                    LVBadge("Loaded", systemImage: "checkmark", tint: LVStyle.ready)
                } else if isDownloaded {
                    LVBadge("Downloaded", systemImage: "arrow.down.circle", tint: .secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? LVStyle.accent.opacity(0.08) : LVStyle.groupedBackground.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? LVStyle.accent.opacity(0.25) : LVStyle.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func whisperModelDetail(_ model: String) -> String {
        switch model {
        case "tiny": return "Fastest · lower accuracy"
        case "base": return "Very fast · good accuracy"
        case "small": return "Fast · great accuracy"
        case "medium": return "Balanced · excellent accuracy"
        case "openai_whisper-large-v3_turbo": return "Recommended · best speed-to-quality"
        case "large-v3": return "Highest accuracy · larger download"
        default: return "Local WhisperKit model"
        }
    }
}

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
        HStack(spacing: 12) {
            Button(action: { if isDownloaded { onSelect() } }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? LVStyle.accent : (isDownloaded ? LVStyle.tertiaryText : Color(nsColor: .quaternaryLabelColor)))
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!isDownloaded)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(model.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    if isRecommended {
                        LVBadge("Recommended", systemImage: "sparkles", tint: LVStyle.accent)
                    }
                    if isDownloaded {
                        LVBadge("Local", systemImage: "checkmark", tint: LVStyle.ready)
                    }
                    if model.isExperimental {
                        LVBadge("Experimental", systemImage: "flask", tint: LVStyle.warning)
                    }
                }
                Text("\(model.qualityLabel) · \(model.family) · \(model.license) · \(String(format: "%.1f", model.estimatedRAMGB)) GB RAM · \(String(format: "%.1f", model.downloadSizeGB)) GB download")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(LVStyle.accent)
                        .frame(maxWidth: 320)
                }
            }

            Spacer()

            if isDownloading {
                ProgressView()
                    .controlSize(.small)
            } else if isDownloaded {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete model")
            } else {
                Button(action: onDownload) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? LVStyle.accent.opacity(0.08) : LVStyle.groupedBackground.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? LVStyle.accent.opacity(0.25) : LVStyle.separator, lineWidth: 0.5)
        )
    }
}

private struct PromptSummaryRow: View {
    let prompt: LLMPrompt
    let isActive: Bool
    let isModified: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive ? LVStyle.accent : LVStyle.tertiaryText)
                    .font(.system(size: 15, weight: .semibold))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(prompt.name)
                            .font(.subheadline.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        if prompt.isPreset {
                            LVBadge("Preset", tint: .secondary)
                        }
                        if isModified {
                            LVBadge("Modified", tint: LVStyle.accent)
                        }
                    }
                    Text(prompt.instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if let keyNumber = prompt.keyNumber {
                    LVKeyCap("\(keyNumber)")
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? LVStyle.accent.opacity(0.08) : LVStyle.groupedBackground.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isActive ? LVStyle.accent.opacity(0.25) : LVStyle.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
