import Foundation

/// バックエンド（`POST /api/document-extract-translate`）と通信し、文書（PDF/DOCX）の
/// 英文抽出（テキスト層抽出 or スキャンOCR）＋目的言語への全訳を行う。
/// 音声の `RemoteTranscriptionTranslationService` の文書版。
@MainActor
final class RemoteDocumentExtractTranslateService: DocumentExtractTranslateService {
    private struct RequestBody: Encodable {
        let fileBase64: String
        let mediaType: String
        let targetLanguage: String
        /// アプリ表示名。管理画面のコンテンツファイル一覧での突き合わせ用（サーバはログに記録するのみ）
        let title: String
    }

    private struct ResponseBody: Decodable {
        let extractedText: String
        let translatedText: String
        let translationLanguage: String
    }

    /// backend の `MAX_DOCUMENT_BYTES`（14MB）と一致。base64 化前の生バイト数で判定し、
    /// 超過はサーバに送らず「短い文書に分割」の案内で失敗させる。
    private static let maxDocumentBytes = 14 * 1024 * 1024

    func process(_ document: Document) async {
        document.processingStatus = .processing
        document.processingErrorMessage = nil

        guard let fileData = try? Data(contentsOf: DocumentStorage.url(fileName: document.documentFileName)) else {
            document.processingStatus = .failed
            document.processingErrorMessage = "Failed to load the document file."
            return
        }

        guard fileData.count <= Self.maxDocumentBytes else {
            let megabytes = Double(fileData.count) / 1024 / 1024
            document.processingStatus = .failed
            document.processingErrorMessage = String(
                format: "Document is too large (%.1f MB, max %d MB). Split it into shorter documents.",
                megabytes, Self.maxDocumentBytes / 1024 / 1024
            )
            return
        }

        let targetLanguage = UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode

        do {
            let data = try await BackendAPI.post(
                path: "api/document-extract-translate",
                body: RequestBody(
                    fileBase64: fileData.base64EncodedString(),
                    mediaType: document.fileKind.mediaType,
                    targetLanguage: targetLanguage,
                    title: document.title
                ),
                timeout: 180
            )
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            document.extractedText = decoded.extractedText
            document.translatedText = decoded.translatedText
            document.translationLanguage = decoded.translationLanguage
            document.processingStatus = .completed
        } catch {
            document.processingStatus = .failed
            document.processingErrorMessage = error.localizedDescription
        }
    }
}
