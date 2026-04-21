import AppKit
import SwiftUI
import SwiftData

final class HistoryWindowController: NSWindowController {
    convenience init(modelContainer: ModelContainer) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LocalVoice — History"
        window.center()
        window.minSize = CGSize(width: 520, height: 360)
        window.contentView = NSHostingView(
            rootView: HistoryView().modelContainer(modelContainer)
        )
        self.init(window: window)
    }
}

// MARK: - Main view

struct HistoryView: View {
    @Query(sort: \TranscriptionRecord.timestamp, order: .reverse)
    private var records: [TranscriptionRecord]

    var body: some View {
        VStack(spacing: 0) {
            StatsBar(records: records)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if records.isEmpty {
                emptyState
            } else {
                recordList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No recordings yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Use the hotkey to start transcribing.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordList: some View {
        List(records) { record in
            RecordRow(record: record)
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) {
            HStack {
                ExportButton(records: records)
                    .padding()
                Spacer()
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// MARK: - Stats bar

struct StatsBar: View {
    let records: [TranscriptionRecord]

    private var totalWords: Int { records.reduce(0) { $0 + $1.wordCount } }

    private var avgWPM: Double? {
        let valid = records.filter { $0.audioDurationSeconds > 0 }
        guard !valid.isEmpty else { return nil }
        let sum = valid.reduce(0.0) { $0 + (Double($1.wordCount) / $1.audioDurationSeconds * 60) }
        return sum / Double(valid.count)
    }

    var body: some View {
        HStack(spacing: 24) {
            StatCell(label: "Recordings", value: "\(records.count)")
            StatCell(label: "Total words", value: "\(totalWords)")
            if let wpm = avgWPM {
                StatCell(label: "Avg WPM", value: String(format: "%.0f", wpm))
            }
            Spacer()
        }
    }
}

struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Record row

struct RecordRow: View {
    let record: TranscriptionRecord

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var wpm: String {
        guard record.audioDurationSeconds > 0 else { return "—" }
        let v = Double(record.wordCount) / record.audioDurationSeconds * 60
        return String(format: "%.0f wpm", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Self.dateFormatter.string(from: record.timestamp))
                    .font(.subheadline.bold())
                Spacer()
                Text(wpm)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                if let app = record.frontmostAppName {
                    Label(app, systemImage: "app.badge")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(record.mode)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(record.mode == AppMode.llmRewrite.rawValue
                        ? Color.purple.opacity(0.15)
                        : Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                if record.mode == AppMode.llmRewrite.rawValue, let pname = record.promptName {
                    Text(pname)
                        .font(.caption2)
                        .foregroundColor(.purple.opacity(0.8))
                }
                if let lang = record.detectedLanguage {
                    Text(lang.uppercased())
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
                Text("\(record.wordCount) words")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1fs", record.audioDurationSeconds))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let text = record.transcribedText {
                Text(text.prefix(120))
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Export

struct ExportButton: View {
    let records: [TranscriptionRecord]

    var body: some View {
        Button("Export CSV…") {
            exportCSV()
        }
        .disabled(records.isEmpty)
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
        let header = "timestamp,app,mode,whisperModel,ollamaModel,wordCount,durationSeconds,wpm,language,promptName,text"
        let rows = records.map { r -> String in
            let wpm: String = r.audioDurationSeconds > 0
                ? String(format: "%.1f", Double(r.wordCount) / r.audioDurationSeconds * 60)
                : ""
            let fields: [String] = [
                iso(r.timestamp),
                escape(r.frontmostAppName ?? ""),
                escape(r.mode),
                escape(r.whisperModel),
                escape(r.ollamaModel ?? ""),
                "\(r.wordCount)",
                String(format: "%.2f", r.audioDurationSeconds),
                wpm,
                escape(r.detectedLanguage ?? ""),
                escape(r.promptName ?? ""),
                escape(r.transcribedText ?? "")
            ]
            return fields.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func escape(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n")
        if needsQuoting {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
