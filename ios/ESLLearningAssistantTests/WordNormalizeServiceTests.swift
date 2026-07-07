import Foundation
import Testing
@testable import ESLLearningAssistant

/// WordNormalizeService の差し替え可能な実装（Phase 2/3 の UI テストで確認UIの出し分けに使う）。
@MainActor
final class MockWordNormalizeService: WordNormalizeService {
    var result: Result<WordNormalization, Error> = .failure(BackendAPIError.serverError(statusCode: 500, message: nil))
    var callCount = 0
    var lastWord: String?
    var lastTargetLanguage: String?
    var lastRegenerate: Bool?

    func normalize(word: String, targetLanguage: String, regenerate: Bool) async throws -> WordNormalization {
        callCount += 1
        lastWord = word
        lastTargetLanguage = targetLanguage
        lastRegenerate = regenerate
        return try result.get()
    }
}

@MainActor
struct WordNormalizeServiceTests {
    /// 簡易版 normalize(word:targetLanguage:) は regenerate=false でプロトコル本体を呼ぶ
    @Test func convenienceOverloadDefaultsToNoRegenerate() async throws {
        let service = MockWordNormalizeService()
        service.result = .success(
            WordNormalization(input: "ran", lemma: "run", status: .inflected, reason: "過去形")
        )

        let normalization = try await service.normalize(word: "ran", targetLanguage: "ja")

        #expect(normalization.lemma == "run")
        #expect(service.callCount == 1)
        #expect(service.lastWord == "ran")
        #expect(service.lastTargetLanguage == "ja")
        #expect(service.lastRegenerate == false)
    }

    /// サービスのエラーは呼び出し側へそのまま伝播する（フォールバックは Phase 2/3 の呼び出し側で行う）
    @Test func propagatesServiceError() async {
        let service = MockWordNormalizeService()
        service.result = .failure(BackendAPIError.unauthorized)

        do {
            _ = try await service.normalize(word: "ran", targetLanguage: "ja")
            Issue.record("エラーが throw されるはず")
        } catch {
            #expect(error is BackendAPIError)
        }
    }
}
