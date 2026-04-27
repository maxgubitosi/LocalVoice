import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

final class HistoryWindowController: NSWindowController {
    convenience init(modelContainer: ModelContainer) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 840, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LocalVoice History"
        window.center()
        window.minSize = CGSize(width: 620, height: 420)
        window.contentView = NSHostingView(
            rootView: HistoryView().modelContainer(modelContainer)
        )
        self.init(window: window)
    }
}

struct HistoryView: View {
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse)
    private var records: [TranscriptionRecord]

    @State private var searchText = ""
    @State private var selectedMode = "All"
    @State private var selectedLanguage = "All"

    private var filteredRecords: [TranscriptionRecord] {
        records.filter { record in
            let matchesMode = selectedMode == "All" || record.mode == selectedMode
            let lang = record.detectedLanguage?.uppercased() ?? "Unknown"
            let matchesLanguage = selectedLanguage == "All" || lang == selectedLanguage
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch: Bool
            if query.isEmpty {
                matchesSearch = true
            } else {
                let haystack = [
                    record.frontmostAppName ?? "",
                    record.mode,
                    record.promptName ?? "",
                    record.detectedLanguage ?? "",
                    record.transcribedText ?? "",
                    record.originalText ?? "",
                    record.refinedText ?? ""
                ].joined(separator: " ")
                matchesSearch = haystack.localizedCaseInsensitiveContains(query)
            }
            return matchesMode && matchesLanguage && matchesSearch
        }
    }

    private var availableModes: [String] {
        ["All"] + Array(Set(records.map(\.mode))).sorted()
    }

    private var availableLanguages: [String] {
        ["All"] + Array(Set(records.map { $0.detectedLanguage?.uppercased() ?? "Unknown" })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if records.isEmpty {
                LVEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: "No recordings yet",
                    message: "Use Right Command to dictate. Your local history and stats will appear here."
                )
            } else if filteredRecords.isEmpty {
                LVEmptyState(
                    systemImage: "magnifyingglass",
                    title: "No matching records",
                    message: "Try a different search, mode, or language filter."
                )
            } else {
                List(filteredRecords) { record in
                    RecordRow(record: record)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                }
                .listStyle(.plain)
            }

            Divider()

            footer
        }
        .background(LVStyle.background)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("History")
                        .font(.title2.weight(.semibold))
                    Text("Local transcription metadata, stats, and optional text content.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ExportButton(records: filteredRecords)
                    .disabled(filteredRecords.isEmpty)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search app, prompt, language, or transcript", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LVStyle.elevatedBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(LVStyle.separator, lineWidth: 0.5)
            )

            HStack(spacing: 12) {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(availableModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)

                Picker("Language", selection: $selectedLanguage) {
                    ForEach(availableLanguages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Spacer()

                StatsStrip(records: filteredRecords)
            }
        }
        .padding(18)
        .background(LVStyle.groupedBackground.opacity(0.62))
    }

    private var footer: some View {
        HStack {
            Text("\(filteredRecords.count) of \(records.count) recordings")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Stored locally with SwiftData")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(LVStyle.groupedBackground.opacity(0.62))
    }
}

private struct StatsStrip: View {
    let records: [TranscriptionRecord]

    private var totalWords: Int { records.reduce(0) { $0 + $1.wordCount } }

    private var avgWPM: Double? {
        let valid = records.filter { $0.audioDurationSeconds > 0 }
        guard !valid.isEmpty else { return nil }
        let sum = valid.reduce(0.0) { $0 + (Double($1.wordCount) / $1.audioDurationSeconds * 60) }
        return sum / Double(valid.count)
    }

    var body: some View {
        HStack(spacing: 8) {
            CompactStat(label: "Recordings", value: "\(records.count)")
            CompactStat(label: "Words", value: "\(totalWords)")
            if let avgWPM {
                CompactStat(label: "Avg WPM", value: String(format: "%.0f", avgWPM))
            }
        }
    }
}

private struct CompactStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LVStyle.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LVStyle.separator, lineWidth: 0.5)
        )
    }
}

private struct RecordRow: View {
    let record: TranscriptionRecord
    @State private var showingOriginal = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var wpm: String {
        guard record.audioDurationSeconds > 0 else { return "-" }
        let value = Double(record.wordCount) / record.audioDurationSeconds * 60
        return String(format: "%.0f wpm", value)
    }

    private var finalText: String? {
        record.finalText
    }

    private var originalText: String? {
        record.originalText
    }

    private var hasOriginalComparison: Bool {
        guard record.mode == AppMode.llmRewrite.rawValue,
              let original = originalText,
              let final = finalText,
              !original.isEmpty,
              original != final
        else { return false }
        return true
    }

    var body: some View {
        LVPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.dateFormatter.string(from: record.timestamp))
                            .font(.subheadline.weight(.semibold))
                        Text(record.frontmostAppName ?? "Unknown app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        LVBadge(record.mode, tint: record.mode == AppMode.llmRewrite.rawValue ? .purple : LVStyle.accent)
                        if let language = record.detectedLanguage {
                            LVBadge(language.uppercased(), tint: .secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Label("\(record.wordCount) words", systemImage: "textformat.size")
                    TimingChip(label: "Audio", value: formatSeconds(record.audioDurationSeconds))
                    if let transcription = record.transcriptionLatencySeconds {
                        TimingChip(label: "Whisper", value: formatSeconds(transcription))
                    }
                    if let refine = record.llmLatencySeconds {
                        TimingChip(label: "Refine", value: formatSeconds(refine))
                    }
                    if let total = record.processingLatencySeconds {
                        TimingChip(label: "Total", value: formatSeconds(total))
                    }
                    Label(wpm, systemImage: "speedometer")
                    if let promptName = record.promptName {
                        Label(promptName, systemImage: "text.badge.checkmark")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let text = finalText, !text.isEmpty {
                    if hasOriginalComparison {
                        Text("Refined")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.82))
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(.top, 2)

                    HStack {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } label: {
                            Label("Copy Text", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)

                        if hasOriginalComparison {
                            Button {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    showingOriginal.toggle()
                                }
                            } label: {
                                Label(showingOriginal ? "Hide Original" : "Show Original", systemImage: "text.viewfinder")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }

                        Spacer()
                    }

                    if hasOriginalComparison, showingOriginal, let originalText {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Original transcript")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(originalText)
                                .font(.caption)
                                .foregroundStyle(.primary.opacity(0.72))
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LVStyle.groupedBackground.opacity(0.45))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(LVStyle.separator, lineWidth: 0.5)
                        )
                    }
                } else {
                    Text("Transcript content was not saved for this recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        if seconds < 1 {
            return "\(Int((seconds * 1000).rounded()))ms"
        }
        return String(format: "%.1fs", seconds)
    }
}

private struct TimingChip: View {
    let label: String
    let value: String

    var body: some View {
        Text("\(label) \(value)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(LVStyle.groupedBackground.opacity(0.65))
            )
    }
}

private struct ExportButton: View {
    let records: [TranscriptionRecord]

    var body: some View {
        Button {
            exportCSV()
        } label: {
            Label("Export CSV", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "localvoice-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let csv = buildCSV()
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func buildCSV() -> String {
        let header = "timestamp,app,mode,whisperModel,llmModel,wordCount,durationSeconds,wpm,language,promptName,transcriptionSeconds,refineSeconds,processingSeconds,originalText,refinedText,finalText"
        let rows = records.map { record -> String in
            let wpm: String = record.audioDurationSeconds > 0
                ? String(format: "%.1f", Double(record.wordCount) / record.audioDurationSeconds * 60)
                : ""
            let fields: [String] = [
                iso(record.timestamp),
                escape(record.frontmostAppName ?? ""),
                escape(record.mode),
                escape(record.whisperModel),
                escape(record.llmModel ?? ""),
                "\(record.wordCount)",
                String(format: "%.2f", record.audioDurationSeconds),
                wpm,
                escape(record.detectedLanguage ?? ""),
                escape(record.promptName ?? ""),
                seconds(record.transcriptionLatencySeconds),
                seconds(record.llmLatencySeconds),
                seconds(record.processingLatencySeconds),
                escape(record.originalText ?? ""),
                escape(record.refinedText ?? ""),
                escape(record.finalText ?? "")
            ]
            return fields.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func seconds(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.3f", value)
    }

    private func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n")
        if needsQuoting {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
