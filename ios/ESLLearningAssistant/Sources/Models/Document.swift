import Foundation
import SwiftData

extension ModelContext {
    /// ドキュメント（PDF/DOCX）を削除する。原本ファイル・SwiftData の Document を消し、
    /// このドキュメントを出典に持つ単語出現（`WordOccurrence`）の `sourceDocument` は
    /// ダングリング参照を避けるため nil 化する（出現自体は残す）。`ModelContext.deleteAudioClip` の文書版。
    /// ドキュメントは複数レッスンに紐付く／紐付け解除後に出現だけ残る場合があるため、
    /// レッスンを辿らず全 `WordOccurrence` から id 一致を拾って nullify する。
    func deleteDocument(_ document: Document) {
        let documentID = document.id
        let occurrences = (try? fetch(FetchDescriptor<WordOccurrence>())) ?? []
        for occurrence in occurrences where occurrence.sourceDocument?.id == documentID {
            occurrence.sourceDocument = nil
        }
        DocumentStorage.delete(fileName: document.documentFileName)
        delete(document)
        saveOrLog()
    }
}

/// 取り込んだ文書の種別。ビューアの出し分け（PDF=PDFView / DOCX=QuickLook）と
/// 抽出経路の判定に使う。新エンティティと同一コミットで入る非オプショナル enum のため
/// 既存行が無く、`processingStatus` と違い storage+computed 方式は不要（直付けで安全。
/// [[swiftdata-codable-migration-pitfall]]）。
enum DocumentKind: String, Codable {
    case pdf
    case docx
}

/// 文書の抽出・翻訳の処理状態。写真OCRの `PhotoProcessingStatus`・音声の `AudioProcessingStatus` と同型。
enum DocumentProcessingStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}

/// iOSの「ファイル」（iCloud・端末内等）から取り込んでアプリの正式データにした文書（PDF/DOCX）。
/// 実体（原本バイナリ）は DocumentStorage（Documents/Documents）にファイルで置き、ここはメタデータのみ持つ。
/// レッスンへの紐付けは任意かつ複数可（音声と同様、複数レッスンへ付けられるしレッスン非依存の
/// ライブラリ文書も許容する）。inverse は `Lesson.documents` 側で定義する。
@Model
final class Document {
    var id: UUID
    /// 表示名。既定は取り込んだファイル名から拡張子を除いたもの。ユーザーが編集可能。
    var title: String
    /// DocumentStorage 内の実ファイル名（`UUID.ext`）
    var documentFileName: String
    /// 文書種別（pdf/docx）。ビューア出し分け・抽出経路の判定に使う。
    var fileKind: DocumentKind
    /// 取り込み元の参照用パス（将来利用のための予備。ファイル取り込みでは付かず nil）。
    var sourcePath: String?
    var byteSize: Int
    var importedAt: Date
    /// 紐付くレッスン（0個以上）。レッスン削除時は nullify されドキュメント自体は残る。
    var lessons: [Lesson] = []

    /// 抽出・翻訳の処理状態。
    /// 実ストレージは optional（NULL 許容カラム）にして将来の軽量マイグレーションを壊さない。
    /// SwiftData は既存行へ Swift の既定値を埋め戻さないため、非オプショナル enum で後付けすると
    /// 旧行の値が NULL のまま残り materialize 時にキャストでクラッシュする（[[swiftdata-codable-migration-pitfall]]）。
    /// 公開 API は computed で NULL を既定値 `.pending` として返す（`AudioClip.processingStatusStorage` 方式）。
    private var processingStatusStorage: DocumentProcessingStatus?
    var processingStatus: DocumentProcessingStatus {
        get { processingStatusStorage ?? .pending }
        set { processingStatusStorage = newValue }
    }
    /// 抽出・翻訳が失敗したときのユーザー向けメッセージ（401時のAPI Secret案内など）。
    /// 以下はいずれも optional 追加のみなので既存データの軽量マイグレーションを維持する。
    var processingErrorMessage: String?
    /// 抽出/OCR された英文（`AudioClip.transcriptText` に相当。Markdown。未処理時は nil）。
    var extractedText: String?
    /// extractedText の全訳（Markdown。未処理時は nil）。
    var translatedText: String?
    /// 訳の言語コード（例: `ja`）。
    var translationLanguage: String?

    init(
        id: UUID = UUID(),
        title: String,
        documentFileName: String,
        fileKind: DocumentKind,
        sourcePath: String? = nil,
        byteSize: Int = 0,
        importedAt: Date = .now,
        lessons: [Lesson] = [],
        processingStatus: DocumentProcessingStatus = .pending,
        processingErrorMessage: String? = nil,
        extractedText: String? = nil,
        translatedText: String? = nil,
        translationLanguage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.documentFileName = documentFileName
        self.fileKind = fileKind
        self.sourcePath = sourcePath
        self.byteSize = byteSize
        self.importedAt = importedAt
        self.lessons = lessons
        self.processingStatus = processingStatus
        self.processingErrorMessage = processingErrorMessage
        self.extractedText = extractedText
        self.translatedText = translatedText
        self.translationLanguage = translationLanguage
    }
}
