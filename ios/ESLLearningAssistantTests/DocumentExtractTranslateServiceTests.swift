import Foundation
import Testing
@testable import ESLLearningAssistant

/// `RemoteDocumentExtractTranslateService` の送信前バリデーション（状態遷移）を検証する。
/// いずれもネットワークに到達する前に `.failed` へ落ちるため、バックエンドを叩かず決定的にテストできる
/// （`DocumentDetailView` の「Extract & Translate」ボタン押下時の pending → processing → failed 分岐に相当）。
/// 抽出/翻訳の成功経路は実 Claude 疎通で確認済み（Phase 2）。`TranscriptionTranslationServiceTests` の文書版。
@MainActor
struct DocumentExtractTranslateServiceTests {
    private func makeDocument(fileName: String, fileKind: DocumentKind = .pdf) -> Document {
        Document(title: "Doc", documentFileName: fileName, fileKind: fileKind)
    }

    /// 実ファイルが存在しなければ、読み込み段階で `.failed`（ネットワークには到達しない）。
    @Test func missingFileFailsBeforeNetwork() async {
        let service = RemoteDocumentExtractTranslateService()
        let document = makeDocument(fileName: "\(UUID().uuidString).pdf")

        await service.process(document)

        #expect(document.processingStatus == .failed)
        #expect(document.processingErrorMessage == "Failed to load the document file.")
        #expect(document.extractedText == nil)
        #expect(document.translatedText == nil)
    }

    /// 14MB 上限を超えるファイルは、送信前に `.failed`（サイズガードは backend の
    /// MAX_DOCUMENT_BYTES と一致）。ネットワークには到達しない。
    @Test func oversizeFileFailsBeforeNetwork() async {
        let service = RemoteDocumentExtractTranslateService()
        // 14MB + 1 バイトの原本を保存し、それを指す Document を作る。
        let oversize = Data(count: 14 * 1024 * 1024 + 1)
        guard let fileName = DocumentStorage.save(data: oversize, ext: "pdf") else {
            Issue.record("failed to write oversize fixture")
            return
        }
        defer { DocumentStorage.delete(fileName: fileName) }
        let document = makeDocument(fileName: fileName)

        await service.process(document)

        #expect(document.processingStatus == .failed)
        #expect(document.processingErrorMessage?.hasPrefix("Document is too large") == true)
        #expect(document.extractedText == nil)
    }
}
