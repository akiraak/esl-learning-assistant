import Foundation

@MainActor
protocol OCRTranslationService {
    func process(_ photo: Photo) async
}
