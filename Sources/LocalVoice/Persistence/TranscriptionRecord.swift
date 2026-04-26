import SwiftData
import Foundation

@Model
final class TranscriptionRecord {
    var timestamp: Date
    var audioDurationSeconds: Double
    var wordCount: Int
    var detectedLanguage: String?
    var frontmostAppBundleID: String?
    var frontmostAppName: String?
    var mode: String
    var whisperModel: String
    @Attribute(originalName: "ollamaModel") var llmModel: String?
    @Attribute(originalName: "ollamaLatencySeconds") var llmLatencySeconds: Double?
    var transcribedText: String?
    var promptName: String?

    init(
        timestamp: Date,
        audioDurationSeconds: Double,
        wordCount: Int,
        detectedLanguage: String?,
        frontmostAppBundleID: String?,
        frontmostAppName: String?,
        mode: String,
        whisperModel: String,
        llmModel: String?,
        llmLatencySeconds: Double?,
        transcribedText: String?,
        promptName: String?
    ) {
        self.timestamp = timestamp
        self.audioDurationSeconds = audioDurationSeconds
        self.wordCount = wordCount
        self.detectedLanguage = detectedLanguage
        self.frontmostAppBundleID = frontmostAppBundleID
        self.frontmostAppName = frontmostAppName
        self.mode = mode
        self.whisperModel = whisperModel
        self.llmModel = llmModel
        self.llmLatencySeconds = llmLatencySeconds
        self.transcribedText = transcribedText
        self.promptName = promptName
    }
}
