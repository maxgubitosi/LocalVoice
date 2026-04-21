import SwiftUI
import AppKit

final class SettingsWindowController: NSWindowController {
    convenience init(settings: AppSettings) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LocalVoice Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        self.init(window: window)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

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
                        Text(model).tag(model)
                    }
                }
                Text("Larger models are more accurate but slower. 'base' recommended for real-time use.")
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

            Section("Privacy") {
                Toggle("Save transcribed text in history", isOn: $settings.saveTranscribedText)
                Text("Text is stored locally only, never sent to any server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400, height: 440)
    }
}
