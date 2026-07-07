import Foundation
import SwiftData

/// 音声クリップの文字起こし・翻訳の処理状態。写真OCRの `PhotoProcessingStatus` と同型。
enum AudioProcessingStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}

/// iOSの「ファイル」（Dropbox・iCloud・端末内）から取り込んでアプリの正式データにした音声クリップ。
/// 実体（音声バイナリ）は AudioStorage（Documents/Audio）にファイルで置き、ここはメタデータのみ持つ。
/// レッスンへの紐付けは任意かつ複数可（単語と同様、複数レッスンへ付けられるしレッスン非依存の
/// ライブラリ音声も許容する）。inverse は `Lesson.audioClips` 側で定義する。
@Model
final class AudioClip {
    var id: UUID
    /// 表示名。既定は取り込んだファイル名から拡張子を除いたもの。ユーザーが編集可能。
    var title: String
    /// AudioStorage 内の実ファイル名（`UUID.ext`）
    var audioFileName: String
    /// 取り込み元の参照用パス（将来利用のための予備。ファイル取り込みでは付かず nil）。
    var sourcePath: String?
    var byteSize: Int
    var importedAt: Date
    /// 紐付くレッスン（0個以上）。レッスン削除時は nullify されクリップ自体は残る。
    var lessons: [Lesson] = []

    /// 文字起こし・翻訳の処理状態。default 付き non-optional（`Word.aiInfoStatus` 前例と同型）で
    /// 既存ストアの軽量マイグレーションを維持する。
    var processingStatus: AudioProcessingStatus = AudioProcessingStatus.pending
    /// 文字起こし・翻訳が失敗したときのユーザー向けメッセージ（401時のAPI Secret案内など）。
    /// 以下はいずれも optional 追加のみなので既存データの軽量マイグレーションを維持する。
    var processingErrorMessage: String?
    /// Gemini による英文逐語文字起こし（Markdown）。
    var transcriptText: String?
    /// transcript の全訳（Markdown）。
    var translatedText: String?
    /// 訳の言語コード（例: `ja`）。
    var translationLanguage: String?

    init(
        id: UUID = UUID(),
        title: String,
        audioFileName: String,
        sourcePath: String? = nil,
        byteSize: Int = 0,
        importedAt: Date = .now,
        lessons: [Lesson] = [],
        processingStatus: AudioProcessingStatus = .pending,
        processingErrorMessage: String? = nil,
        transcriptText: String? = nil,
        translatedText: String? = nil,
        translationLanguage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.audioFileName = audioFileName
        self.sourcePath = sourcePath
        self.byteSize = byteSize
        self.importedAt = importedAt
        self.lessons = lessons
        self.processingStatus = processingStatus
        self.processingErrorMessage = processingErrorMessage
        self.transcriptText = transcriptText
        self.translatedText = translatedText
        self.translationLanguage = translationLanguage
    }
}
