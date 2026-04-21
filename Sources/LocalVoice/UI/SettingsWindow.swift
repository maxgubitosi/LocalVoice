import SwiftUI
import AppKit

final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings, promptStore: PromptStore) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LocalVoice Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, promptStore: promptStore))
        self.init(window: window)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let promptStore: PromptStore

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

            Section("Transcription") {
                Picker("Model", selection: $settings.whisperModel) {
                    ForEach(TranscriptionEngine.availableModels, id: \.self) { model in
                        Text(TranscriptionEngine.modelDisplayNames[model] ?? model).tag(model)
                    }
                }
                Text("'large-v3-turbo' para mejor calidad. 'base' o 'small' para uso en tiempo real.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Language", selection: $settings.transcriptionLanguage) {
                    ForEach(TranscriptionLanguage.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Ollama (LLM Rewrite Mode)") {
                TextField("Model name", text: $settings.ollamaModel)
                Text("e.g. llama3.2, mistral, phi3. Run: ollama pull <model>")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("LLM Prompt") {
                Picker("Active Prompt", selection: $settings.activePromptID) {
                    ForEach(promptStore.prompts) { p in
                        Text(p.name).tag(Optional(p.id))
                    }
                }
                Text("Hold Right ⌘ + number key to temporarily use a different prompt.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Privacy") {
                Toggle("Save transcribed text in history", isOn: $settings.saveTranscribedText)
                Text("Text is stored locally only, never sent to any server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400, height: 520)
    }
}
