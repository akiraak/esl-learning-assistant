import Foundation

/// バックエンド（`POST /api/transcribe-translate`）と通信し、音声クリップの
/// 英文逐語文字起こし（Gemini）＋日本語全訳（Claude）を行う。
/// 写真OCRの `RemoteOCRTranslationService` の音声版。
@MainActor
final class RemoteTranscriptionTranslationService: TranscriptionTranslationService {
    private struct RequestBody: Encodable {
        let audioBase64: String
        let mediaType: String
        let targetLanguage: String
    }

    private struct ResponseBody: Decodable {
        let englishText: String
        let translatedText: String
        let translationLanguage: String
    }

    /// Gemini がインライン入力で受け付ける音声形式（拡張子→mimeType）。
    /// backend の `SUPPORTED_AUDIO_MIME_EXTENSIONS`（`transcribe.ts`）と一致させること。
    /// m4a/mp4 コンテナは inline 非対応のため v1 では未対応（送信前に弾く）。
    private static let mimeTypesByExtension: [String: String] = [
        "wav": "audio/wav",
        "mp3": "audio/mp3",
        "aac": "audio/aac",
        "aif": "audio/aiff",
        "aiff": "audio/aiff",
        "ogg": "audio/ogg",
        "flac": "audio/flac",
    ]

    /// backend の `MAX_AUDIO_BYTES`（14MB）と一致。base64 化前の生バイト数で判定し、
    /// 超過はサーバに送らず「短いクリップに分割」の案内で失敗させる。
    private static let maxAudioBytes = 14 * 1024 * 1024

    /// エラーメッセージ用の対応フォーマット一覧（人向け表記）。
    private static let supportedFormatsLabel = "WAV, MP3, AAC, AIFF, OGG, FLAC"

    func process(_ clip: AudioClip) async {
        clip.processingStatus = .processing
        clip.processingErrorMessage = nil

        let ext = (clip.audioFileName as NSString).pathExtension.lowercased()
        guard let mediaType = Self.mimeTypesByExtension[ext] else {
            clip.processingStatus = .failed
            clip.processingErrorMessage = ext.isEmpty
                ? "Unsupported audio format. Supported formats: \(Self.supportedFormatsLabel)."
                : "Unsupported audio format “.\(ext)”. Supported formats: \(Self.supportedFormatsLabel)."
            return
        }

        guard let audioData = try? Data(contentsOf: AudioStorage.url(fileName: clip.audioFileName)) else {
            clip.processingStatus = .failed
            clip.processingErrorMessage = "Failed to load the audio file."
            return
        }

        guard audioData.count <= Self.maxAudioBytes else {
            let megabytes = Double(audioData.count) / 1024 / 1024
            clip.processingStatus = .failed
            clip.processingErrorMessage = String(
                format: "Audio is too large (%.1f MB, max %d MB). Split it into shorter clips.",
                megabytes, Self.maxAudioBytes / 1024 / 1024
            )
            return
        }

        let targetLanguage = UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode

        do {
            let data = try await BackendAPI.post(
                path: "api/transcribe-translate",
                body: RequestBody(
                    audioBase64: audioData.base64EncodedString(),
                    mediaType: mediaType,
                    targetLanguage: targetLanguage
                ),
                timeout: 180
            )
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            clip.transcriptText = decoded.englishText
            clip.translatedText = decoded.translatedText
            clip.translationLanguage = decoded.translationLanguage
            clip.processingStatus = .completed
        } catch {
            clip.processingStatus = .failed
            clip.processingErrorMessage = error.localizedDescription
        }
    }
}
