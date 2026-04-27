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
    var originalText: String?
    var refinedText: String?
    var transcriptionLatencySeconds: Double?
    var processingLatencySeconds: Double?
    var promptName: String?

    var finalText: String? {
        transcribedText ?? refinedText ?? originalText
    }

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
        originalText: String? = nil,
        refinedText: String? = nil,
        transcriptionLatencySeconds: Double? = nil,
        processingLatencySeconds: Double? = nil,
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
        self.originalText = originalText
        self.refinedText = refinedText
        self.transcriptionLatencySeconds = transcriptionLatencySeconds
        self.processingLatencySeconds = processingLatencySeconds
        self.promptName = promptName
    }
}
