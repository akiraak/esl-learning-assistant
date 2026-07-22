import Foundation

/// バックエンドの文書抽出＋翻訳ジョブ API と通信し、文書（PDF/DOCX）の
/// 英文抽出（テキスト層抽出 or スキャンOCR）＋目的言語への全訳を行う。
/// 音声の `RemoteTranscriptionTranslationService` の文書版。
///
/// 旧実装は同期 `POST /api/document-extract-translate` の完了を待つ設計で、多ページの
/// スキャン PDF では Cloudflare の 100 秒タイムアウト（HTTP 524）に達して失敗していた。
/// 現在は `POST /api/document-extract-translate/jobs` でジョブを受け付けてもらい（202）、
/// `GET /api/document-extract-translate/jobs/{jobId}` を数秒間隔でポーリングして結果を得る
/// （docs/plans/pdf-extract-translate-524-timeout.md）。
@MainActor
final class RemoteDocumentExtractTranslateService: DocumentExtractTranslateService {
    private struct RequestBody: Encodable {
        let fileBase64: String
        let mediaType: String
        let targetLanguage: String
        /// アプリ表示名。管理画面のコンテンツファイル一覧での突き合わせ用（サーバはログに記録するのみ）
        let title: String
    }

    private struct JobAcceptedBody: Decodable {
        let jobId: String
    }

    /// ジョブ状態レスポンス。status が "success" のときだけ結果フィールドが入る。
    private struct JobStatusBody: Decodable {
        let status: String
        let extractedText: String?
        let translatedText: String?
        let translationLanguage: String?
        let error: String?
    }

    private struct ExtractResult {
        let extractedText: String
        let translatedText: String
        let translationLanguage: String
    }

    private enum JobPollError: LocalizedError {
        case jobFailed(String)
        case jobNotFound
        case timedOut
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .jobFailed(let message):
                message
            case .jobNotFound:
                "The server lost track of this job (it may have restarted). Try again."
            case .timedOut:
                "Document processing timed out. Try again with a shorter document."
            case .unexpectedResponse:
                "Unexpected response from the server."
            }
        }
    }

    /// backend の `MAX_DOCUMENT_BYTES`（14MB）と一致。base64 化前の生バイト数で判定し、
    /// 超過はサーバに送らず「短い文書に分割」の案内で失敗させる。
    private static let maxDocumentBytes = 14 * 1024 * 1024

    /// ジョブ状態のポーリング間隔と打ち切り。サーバ側のジョブ保持は 30 分
    /// （`DOCUMENT_JOB_TTL_MS`）なので、打ち切り 15 分はその範囲に収まる。
    private static let pollIntervalSeconds: UInt64 = 3
    private static let maxPollDuration: TimeInterval = 15 * 60
    /// 一時的な通信エラー（電波状況など）はこの回数まで連続して許容する
    private static let maxConsecutivePollFailures = 3

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
            // ジョブ投入（アップロードは base64 で最大 ~19MB になるため余裕を持ったタイムアウト）
            let accepted = try await BackendAPI.post(
                path: "api/document-extract-translate/jobs",
                body: RequestBody(
                    fileBase64: fileData.base64EncodedString(),
                    mediaType: document.fileKind.mediaType,
                    targetLanguage: targetLanguage,
                    title: document.title
                ),
                timeout: 180
            )
            let jobId = try JSONDecoder().decode(JobAcceptedBody.self, from: accepted).jobId

            let result = try await Self.pollJobUntilSettled(jobId: jobId)
            document.extractedText = result.extractedText
            document.translatedText = result.translatedText
            document.translationLanguage = result.translationLanguage
            document.processingStatus = .completed
        } catch {
            document.processingStatus = .failed
            document.processingErrorMessage = error.localizedDescription
        }
    }

    /// ジョブが success / failed になるまでポーリングする。processing の間は待ち続け、
    /// 打ち切り時間を超えたら timedOut を投げる。
    private static func pollJobUntilSettled(jobId: String) async throws -> ExtractResult {
        let deadline = Date().addingTimeInterval(maxPollDuration)
        var consecutiveFailures = 0

        while Date() < deadline {
            try await Task.sleep(nanoseconds: pollIntervalSeconds * 1_000_000_000)

            let data: Data
            do {
                data = try await BackendAPI.get(path: "api/document-extract-translate/jobs/\(jobId)")
                consecutiveFailures = 0
            } catch {
                // ジョブ消滅（サーバ再起動）と認証失敗はリトライしても回復しないので即失敗
                if case BackendAPIError.serverError(statusCode: 404, message: _) = error {
                    throw JobPollError.jobNotFound
                }
                if case BackendAPIError.unauthorized = error {
                    throw error
                }
                consecutiveFailures += 1
                if consecutiveFailures >= maxConsecutivePollFailures {
                    throw error
                }
                continue
            }

            let status = try JSONDecoder().decode(JobStatusBody.self, from: data)
            switch status.status {
            case "processing":
                continue
            case "success":
                guard let extractedText = status.extractedText,
                      let translatedText = status.translatedText,
                      let translationLanguage = status.translationLanguage else {
                    throw JobPollError.unexpectedResponse
                }
                return ExtractResult(
                    extractedText: extractedText,
                    translatedText: translatedText,
                    translationLanguage: translationLanguage
                )
            case "failed":
                throw JobPollError.jobFailed(status.error ?? "Document processing failed on the server.")
            default:
                throw JobPollError.unexpectedResponse
            }
        }
        throw JobPollError.timedOut
    }
}
