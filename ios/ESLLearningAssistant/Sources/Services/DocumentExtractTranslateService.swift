import Foundation

/// 文書（`Document`, PDF/DOCX）の英文抽出（テキスト層抽出 or スキャンOCR）＋目的言語への全訳を行う
/// サービスの抽象。音声の `TranscriptionTranslationService`・写真OCRの `OCRTranslationService` の文書版。
/// `process` は `document` の `processingStatus` と結果フィールドを直接更新する
/// （@MainActor で SwiftData を安全に書き換える）。
///
/// 呼び出しは「`Document` を渡すと抽出＋翻訳して状態遷移する」1メソッドに閉じ込めてある。
/// v1 は `DocumentDetailView` の手動ボタンから呼ぶ（Phase 4）。将来は取り込み完了直後
/// （`DocumentFileImporter`）にも同じメソッドを呼ぶだけで自動化できる。
@MainActor
protocol DocumentExtractTranslateService {
    func process(_ document: Document) async
}
