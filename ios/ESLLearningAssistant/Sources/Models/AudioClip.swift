import Foundation
import SwiftData

extension ModelContext {
    /// 音声クリップを削除する。音声ファイル・SwiftData の AudioClip を消し、
    /// このクリップを出典に持つ単語出現（`WordOccurrence`）の `sourceAudio` は
    /// ダングリング参照を避けるため nil 化する（出現自体は残す）。`ModelContext.deletePhoto` の音声版。
    /// クリップは複数レッスンに紐付く／紐付け解除後に出現だけ残る場合があるため、
    /// レッスンを辿らず全 `WordOccurrence` から id 一致を拾って nullify する。
    func deleteAudioClip(_ clip: AudioClip) {
        let clipID = clip.id
        let occurrences = (try? fetch(FetchDescriptor<WordOccurrence>())) ?? []
        for occurrence in occurrences where occurrence.sourceAudio?.id == clipID {
            occurrence.sourceAudio = nil
        }
        AudioStorage.delete(fileName: clip.audioFileName)
        delete(clip)
        saveOrLog()
    }
}

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

    /// 文字起こし・翻訳の処理状態。
    /// 実ストレージは optional（NULL 許容カラム）にして既存行の軽量マイグレーションを壊さない。
    /// SwiftData は既存行へ Swift の既定値を埋め戻さないため、非オプショナル enum で追加すると
    /// 旧行の値が NULL のまま残り、materialize 時に「NULL → 非オプショナル enum」のキャストで
    /// クラッシュする（[[swiftdata-codable-migration-pitfall]]）。公開 API は computed で NULL を
    /// 既定値 `.pending` として返す（`WordReviewState.stepIndexStorage` 方式）。
    private var processingStatusStorage: AudioProcessingStatus?
    var processingStatus: AudioProcessingStatus {
        get { processingStatusStorage ?? .pending }
        set { processingStatusStorage = newValue }
    }
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
