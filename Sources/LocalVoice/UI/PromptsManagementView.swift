import SwiftUI

struct PromptsManagementView: View {
    @ObservedObject var promptStore: PromptStore
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: UUID?
    @State private var draftName = ""
    @State private var draftInstruction = ""
    @State private var draftKeyNumber: Int? = nil

    private var selectedPrompt: LLMPrompt? {
        promptStore.prompts.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
            detailPanel
                .frame(minWidth: 420)
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(LVStyle.background)
        .onAppear {
            if selectedID == nil, let first = promptStore.prompts.first {
                selectedID = first.id
                loadDraft(from: first)
            } else {
                loadDraft(from: selectedPrompt)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prompts")
                    .font(.title3.weight(.semibold))
                Text("Reusable local rewrite instructions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    promptSection(
                        title: "Presets",
                        prompts: promptStore.prompts.filter(\.isPreset)
                    )
                    promptSection(
                        title: "Custom",
                        prompts: promptStore.prompts.filter { !$0.isPreset }
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: selectedID) { _, _ in loadDraft(from: selectedPrompt) }

            Divider()

            HStack {
                Button(action: addNewPrompt) {
                    Label("New Prompt", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(12)
        }
        .background(LVStyle.groupedBackground)
    }

    private func promptSection(title: String, prompts: [LLMPrompt]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            if prompts.isEmpty {
                Text("No custom prompts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            } else {
                ForEach(prompts) { prompt in
                    promptRow(prompt)
                }
            }
        }
    }

    private func promptRow(_ prompt: LLMPrompt) -> some View {
        let isSelected = selectedID == prompt.id
        let isActive = prompt.id == settings.activePromptID

        return Button {
            selectedID = prompt.id
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(prompt.name)
                        .font(.subheadline.weight(isSelected || isActive ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if let keyNumber = prompt.keyNumber {
                            PromptShortcutChip(number: keyNumber, isSelected: isSelected)
                        }
                        if promptStore.isModified(prompt) {
                            Text("Modified")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(LVStyle.accent)
                        }
                    }
                    .frame(minHeight: 20, alignment: .leading)
                }
                Spacer(minLength: 10)
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(isSelected ? LVStyle.accent : LVStyle.ready)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? LVStyle.accent.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? LVStyle.accent.opacity(0.28) : Color.clear, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detailPanel: some View {
        Group {
            if let prompt = selectedPrompt {
                promptDetail(prompt)
            } else {
                LVEmptyState(
                    systemImage: "text.badge.plus",
                    title: "Select a prompt",
                    message: "Choose a preset or custom prompt to edit its local rewrite instruction."
                )
            }
        }
    }

    private func promptDetail(_ prompt: LLMPrompt) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(prompt.isPreset ? "Preset Prompt" : "Custom Prompt")
                        .font(.title3.weight(.semibold))
                    Text("Prompts are sent to the local MLX model after Whisper transcription.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    if prompt.isPreset {
                        LVBadge("Preset", tint: .secondary)
                    }
                    if promptStore.isModified(prompt) {
                        LVBadge("Modified", tint: LVStyle.accent)
                    }
                    if settings.activePromptID == prompt.id {
                        LVBadge("Active", systemImage: "checkmark", tint: LVStyle.ready)
                    }
                }
            }

            LVPanel {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Name")
                            .font(.subheadline.weight(.semibold))
                        TextField("Prompt name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitDraft() }
                            .onChange(of: draftName) { _, _ in commitDraft() }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Instruction")
                            .font(.subheadline.weight(.semibold))
                        Text("This is the editable task only. At runtime LocalVoice adds language, app context, safety rules, and the quoted dictation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextEditor(text: $draftInstruction)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(LVStyle.groupedBackground.opacity(0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(LVStyle.separator, lineWidth: 0.5)
                            )
                            .onChange(of: draftInstruction) { _, _ in commitDraft() }
                    }

                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Shortcut")
                                .font(.subheadline.weight(.semibold))
                            Text("Use while recording by pressing the number key.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("Shortcut", selection: $draftKeyNumber) {
                            Text("None").tag(Optional<Int>.none)
                            ForEach(1...9, id: \.self) { number in
                                Text("\(number)").tag(Optional(number))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 110)
                        .onChange(of: draftKeyNumber) { _, _ in commitDraft() }
                    }
                }
            }

            LVPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Runtime prompt preview")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(runtimePromptPreview(for: prompt))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LVStyle.groupedBackground.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(LVStyle.separator, lineWidth: 0.5)
                    )
                }
            }

            HStack {
                Button {
                    settings.activePromptID = prompt.id
                } label: {
                    Label("Make Active", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.activePromptID == prompt.id)

                if prompt.isPreset, promptStore.isModified(prompt) {
                    Button("Revert to Default") {
                        promptStore.revertToDefault(prompt)
                        loadDraft(from: promptStore.prompts.first { $0.id == prompt.id })
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if !prompt.isPreset {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .padding(22)
        .onChange(of: selectedID) { _, _ in loadDraft(from: selectedPrompt) }
    }

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
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? prompt.name : draftName,
            instruction: draftInstruction,
            isPreset: prompt.isPreset,
            keyNumber: draftKeyNumber
        )
        promptStore.update(updated)
    }

    private func runtimePromptPreview(for prompt: LLMPrompt) -> String {
        let previewPrompt = LLMPrompt(
            id: prompt.id,
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? prompt.name : draftName,
            instruction: draftInstruction,
            isPreset: prompt.isPreset,
            keyNumber: draftKeyNumber
        )

        return PromptComposer.compose(
            transcript: "Example dictated text appears here.",
            prompt: previewPrompt,
            appContext: "Active App",
            detectedLanguage: nil,
            modelID: settings.llmModel
        )
    }

    private func addNewPrompt() {
        let newPrompt = LLMPrompt(
            id: UUID(),
            name: "New Prompt",
            instruction: "Rewrite the transcript for clarity. Preserve the user's intent and return only the final text.",
            isPreset: false,
            keyNumber: nil
        )
        promptStore.add(newPrompt)
        selectedID = newPrompt.id
        settings.activePromptID = newPrompt.id
        loadDraft(from: newPrompt)
    }

    private func deleteSelected() {
        guard let prompt = selectedPrompt, !prompt.isPreset else { return }
        promptStore.delete(prompt)
        if settings.activePromptID == prompt.id {
            settings.activePromptID = promptStore.prompts.first?.id
        }
        let nextPrompt = promptStore.prompts.last { !$0.isPreset }
            ?? promptStore.prompts.first
        selectedID = nextPrompt?.id
        loadDraft(from: nextPrompt)
    }
}

private struct PromptShortcutChip: View {
    let number: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isSelected ? LVStyle.accent : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.75) : LVStyle.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(LVStyle.separator, lineWidth: 0.5)
        )
    }
}
