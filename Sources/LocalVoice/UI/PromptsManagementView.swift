import SwiftUI

struct PromptsManagementView: View {
    @ObservedObject var promptStore: PromptStore
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: UUID?
    @State private var draftName: String = ""
    @State private var draftInstruction: String = ""
    @State private var draftKeyNumber: Int? = nil

    private var selectedPrompt: LLMPrompt? {
        promptStore.prompts.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 170, idealWidth: 190, maxWidth: 220)
            detailPanel
                .frame(minWidth: 300)
        }
        .onAppear {
            if selectedID == nil { selectedID = promptStore.prompts.first?.id }
            loadDraft(from: selectedPrompt)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedID) {
                Section("Presets") {
                    ForEach(promptStore.prompts.filter(\.isPreset)) { p in
                        promptRow(p)
                    }
                }
                Section("Custom") {
                    ForEach(promptStore.prompts.filter { !$0.isPreset }) { p in
                        promptRow(p)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedID) { _, _ in loadDraft(from: selectedPrompt) }

            Divider()
            Button(action: addNewPrompt) {
                Label("New Prompt", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    private func promptRow(_ p: LLMPrompt) -> some View {
        HStack {
            Text(p.name)
            Spacer()
            if promptStore.isModified(p) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
            }
            if let n = p.keyNumber {
                Text("[\(n)]")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .tag(p.id)
    }

    // MARK: - Detail

    private var detailPanel: some View {
        Group {
            if let prompt = selectedPrompt {
                promptDetail(prompt)
            } else {
                Text("Select a prompt")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func promptDetail(_ prompt: LLMPrompt) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(prompt.isPreset ? "Preset" : "Custom Prompt")
                    .font(.headline)
                Spacer()
                if prompt.isPreset && promptStore.isModified(prompt) {
                    Text("Modified")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .cornerRadius(5)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundColor(.secondary)
                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitDraft() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Instruction").font(.caption).foregroundColor(.secondary)
                TextEditor(text: $draftInstruction)
                    .font(.system(size: 12))
                    .frame(minHeight: 120)
                    .border(Color(nsColor: .separatorColor), width: 0.5)
                    .onChange(of: draftInstruction) { _, _ in commitDraft() }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcut key  (Right ⌘ + number)").font(.caption).foregroundColor(.secondary)
                Picker("", selection: $draftKeyNumber) {
                    Text("None").tag(Optional<Int>.none)
                    ForEach(1...9, id: \.self) { n in
                        Text("\(n)").tag(Optional(n))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .onChange(of: draftKeyNumber) { _, _ in commitDraft() }
            }

            Spacer()

            HStack {
                if prompt.isPreset {
                    if promptStore.isModified(prompt) {
                        Button("Revert to Default") {
                            promptStore.revertToDefault(prompt)
                            loadDraft(from: promptStore.prompts.first { $0.id == prompt.id })
                        }
                        .foregroundColor(.secondary)
                    }
                } else {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onChange(of: selectedID) { _, _ in loadDraft(from: selectedPrompt) }
    }

    // MARK: - Actions

    private func loadDraft(from prompt: LLMPrompt?) {
        guard let prompt else { return }
        draftName = prompt.name
        draftInstruction = prompt.instruction
        draftKeyNumber = prompt.keyNumber
    }

    private func commitDraft() {
        guard let prompt = selectedPrompt else { return }
        let updated = LLMPrompt(
            id: prompt.id,
            name: draftName.isEmpty ? prompt.name : draftName,
            instruction: draftInstruction,
            isPreset: prompt.isPreset,
            keyNumber: draftKeyNumber
        )
        promptStore.update(updated)
    }

    private func addNewPrompt() {
        let newPrompt = LLMPrompt(
            id: UUID(),
            name: "New Prompt",
            instruction: "",
            isPreset: false,
            keyNumber: nil
        )
        promptStore.add(newPrompt)
        selectedID = newPrompt.id
    }

    private func deleteSelected() {
        guard let prompt = selectedPrompt, !prompt.isPreset else { return }
        promptStore.delete(prompt)
        if settings.activePromptID == prompt.id {
            settings.activePromptID = promptStore.prompts.first?.id
        }
        selectedID = promptStore.prompts.last { !$0.isPreset }?.id
            ?? promptStore.prompts.first?.id
    }
}
