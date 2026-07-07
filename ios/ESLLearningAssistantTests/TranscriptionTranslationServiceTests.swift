import Foundation
import Testing
@testable import ESLLearningAssistant

/// `RemoteTranscriptionTranslationService` の送信前バリデーション（状態遷移）を検証する。
/// これらのケースはいずれもネットワーク・実ファイルに到達する前に `.failed` へ落ちるため、
/// バックエンドを叩かず決定的にテストできる（AudioDetailView の「文字起こし」ボタン押下時の
/// pending → processing → failed の分岐に相当）。
@MainActor
struct TranscriptionTranslationServiceTests {
    private func makeClip(audioFileName: String) -> AudioClip {
        AudioClip(title: "Clip", audioFileName: audioFileName)
    }

    /// 未対応拡張子（m4a/mp4 コンテナは v1 では inline 非対応）は、mimeType 判定で
    /// ネットワークに送る前に `.failed` になる。
    @Test func unsupportedFormatFailsBeforeNetwork() async {
        let service = RemoteTranscriptionTranslationService()
        let clip = makeClip(audioFileName: "\(UUID().uuidString).m4a")

        await service.process(clip)

        #expect(clip.processingStatus == .failed)
        #expect(clip.processingErrorMessage?.contains("Unsupported audio format") == true)
        #expect(clip.transcriptText == nil)
    }

    /// 拡張子のない音声ファイル名も未対応として `.failed`。
    @Test func missingExtensionFailsBeforeNetwork() async {
        let service = RemoteTranscriptionTranslationService()
        let clip = makeClip(audioFileName: UUID().uuidString)

        await service.process(clip)

        #expect(clip.processingStatus == .failed)
    }

    /// 対応拡張子（wav）は mimeType 判定を通過するが、実ファイルが無ければ読み込みで
    /// `.failed` になる（ネットワークには到達しない）。wav が受理される経路の裏取りも兼ねる。
    @Test func supportedFormatWithMissingFileFailsOnLoad() async {
        let service = RemoteTranscriptionTranslationService()
        // AudioStorage に存在しないランダムなファイル名を使い、読み込み失敗へ確実に倒す
        let clip = makeClip(audioFileName: "\(UUID().uuidString).wav")

        await service.process(clip)

        #expect(clip.processingStatus == .failed)
        #expect(clip.processingErrorMessage == "Failed to load the audio file.")
    }
}
