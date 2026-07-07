import Foundation

/// 音声クリップ（`AudioClip`）の英文文字起こし＋日本語全訳を行うサービスの抽象。
/// 写真OCRの `OCRTranslationService` の音声版。`process` は `clip` の
/// `processingStatus` と結果フィールドを直接更新する（@MainActor で SwiftData を安全に書き換える）。
@MainActor
protocol TranscriptionTranslationService {
    func process(_ clip: AudioClip) async
}
