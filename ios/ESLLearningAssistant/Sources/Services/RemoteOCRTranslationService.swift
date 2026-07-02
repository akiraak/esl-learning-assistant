import Foundation

/// バックエンド（仕様書5.2章、Claude API中継）と通信し、撮影画像のOCR・翻訳を行う。
@MainActor
final class RemoteOCRTranslationService: OCRTranslationService {
    private struct RequestBody: Encodable {
        let imageBase64: String
        let mediaType: String
        let targetLanguage: String
    }

    private struct ResponseBody: Decodable {
        let ocrText: String
        let translatedText: String
        let translationLanguage: String
    }

    func process(_ photo: Photo) async {
        photo.processingStatus = .processing
        photo.processingErrorMessage = nil

        guard let imageData = PhotoStorage.loadData(fileName: photo.imageFileName) else {
            photo.processingStatus = .failed
            photo.processingErrorMessage = "Failed to load the photo image."
            return
        }

        let targetLanguage = UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode

        do {
            let data = try await BackendAPI.post(
                path: "api/ocr-translate",
                body: RequestBody(
                    imageBase64: imageData.base64EncodedString(),
                    mediaType: "image/jpeg",
                    targetLanguage: targetLanguage
                )
            )
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            photo.ocrText = decoded.ocrText
            photo.translatedText = decoded.translatedText
            photo.translationLanguage = decoded.translationLanguage
            photo.processingStatus = .completed
        } catch {
            photo.processingStatus = .failed
            photo.processingErrorMessage = error.localizedDescription
        }
    }
}
