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

        guard let imageData = PhotoStorage.loadData(fileName: photo.imageFileName) else {
            photo.processingStatus = .failed
            return
        }

        let baseURLString = UserDefaults.standard.string(forKey: AppSettingsKeys.backendBaseURL)
            ?? AppSettingsKeys.defaultBackendBaseURL
        let targetLanguage = UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode

        guard let url = URL(string: baseURLString)?.appendingPathComponent("api/ocr-translate") else {
            photo.processingStatus = .failed
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(
            RequestBody(
                imageBase64: imageData.base64EncodedString(),
                mediaType: "image/jpeg",
                targetLanguage: targetLanguage
            )
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                photo.processingStatus = .failed
                return
            }
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
            photo.ocrText = decoded.ocrText
            photo.translatedText = decoded.translatedText
            photo.translationLanguage = decoded.translationLanguage
            photo.processingStatus = .completed
        } catch {
            photo.processingStatus = .failed
        }
    }
}
