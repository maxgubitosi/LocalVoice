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
    var ollamaModel: String?
    var ollamaLatencySeconds: Double?
    var transcribedText: String?

    init(
        timestamp: Date,
        audioDurationSeconds: Double,
        wordCount: Int,
        detectedLanguage: String?,
        frontmostAppBundleID: String?,
        frontmostAppName: String?,
        mode: String,
        whisperModel: String,
        ollamaModel: String?,
        ollamaLatencySeconds: Double?,
        transcribedText: String?
    ) {
        self.timestamp = timestamp
        self.audioDurationSeconds = audioDurationSeconds
        self.wordCount = wordCount
        self.detectedLanguage = detectedLanguage
        self.frontmostAppBundleID = frontmostAppBundleID
        self.frontmostAppName = frontmostAppName
        self.mode = mode
        self.whisperModel = whisperModel
        self.ollamaModel = ollamaModel
        self.ollamaLatencySeconds = ollamaLatencySeconds
        self.transcribedText = transcribedText
    }
}
