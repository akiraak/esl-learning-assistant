import Foundation

@MainActor
protocol OCRTranslationService {
    func process(_ photo: Photo) async
}

/// バックエンド（仕様書5.2章のClaude API中継）が未実装のため、固定テキストを返すスタブ。
/// 実装が完成したら本サービスを差し替える。
@MainActor
final class MockOCRTranslationService: OCRTranslationService {
    func process(_ photo: Photo) async {
        photo.processingStatus = .processing
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        photo.ocrText = "This is a sample sentence from the textbook. I have a pen."
        photo.translatedText = "これは教科書のサンプル文です。私はペンを持っています。"
        photo.translationLanguage = "ja"
        photo.processingStatus = .completed
    }
}
