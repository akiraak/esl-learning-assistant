import Foundation
import SwiftData

enum PhotoProcessingStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}

@Model
final class Photo {
    var id: UUID
    var lesson: Lesson
    var imageFileName: String
    var capturedAt: Date
    var processingStatus: PhotoProcessingStatus
    /// OCR・翻訳が失敗したときのユーザー向けメッセージ（401時のAPI Secret案内など）。
    /// optional追加のみなので既存データの軽量マイグレーションを維持する。
    var processingErrorMessage: String?
    var ocrText: String?
    var translatedText: String?
    var translationLanguage: String?

    init(
        id: UUID = UUID(),
        lesson: Lesson,
        imageFileName: String,
        capturedAt: Date = .now,
        processingStatus: PhotoProcessingStatus = .pending,
        ocrText: String? = nil,
        translatedText: String? = nil,
        translationLanguage: String? = nil
    ) {
        self.id = id
        self.lesson = lesson
        self.imageFileName = imageFileName
        self.capturedAt = capturedAt
        self.processingStatus = processingStatus
        self.ocrText = ocrText
        self.translatedText = translatedText
        self.translationLanguage = translationLanguage
    }
}
