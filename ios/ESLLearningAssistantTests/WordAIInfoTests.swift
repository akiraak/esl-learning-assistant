import SwiftData
import XCTest
@testable import ESLLearningAssistant

/// バックエンド /api/word-info の実レスポンス形（backend/src/wordInfo.ts）との整合を確認する。
final class WordAIInfoDecodingTests: XCTestCase {
    // 実バックエンドのレスポンスを元にしたフィクスチャ（optional項目のnullを含む）
    private let responseJSON = """
    {
      "wordInfo": {
        "senses": [
          {
            "meaning": "(事業を)経営する、運営する",
            "englishDefinition": "to manage or operate a business",
            "partOfSpeech": "動詞",
            "note": "目的語に事業や店舗などを取る。"
          },
          {
            "meaning": "走る、駆ける",
            "englishDefinition": "to move quickly on foot",
            "partOfSpeech": "動詞",
            "note": null
          }
        ],
        "pronunciation": { "ipa": "/rʌn/", "syllables": null },
        "inflections": [
          { "form": "過去形", "text": "ran" },
          { "form": "過去分詞", "text": "run" }
        ],
        "examples": [
          { "english": "My uncle runs a small bakery.", "translation": "叔父は小さなベーカリーを経営しています。" },
          { "english": "The engine runs smoothly.", "translation": "エンジンがスムーズに動いています。" }
        ],
        "collocations": ["run a business", "run smoothly"],
        "synonyms": ["operate", "manage"],
        "antonyms": ["stop"],
        "usageNote": "「経営する」の意味では継続的な運営を指す。",
        "cefrLevel": "A1",
        "etymology": null,
        "register": null,
        "commonMistakes": "「run away」と混同しないこと。"
      },
      "model": "claude-haiku-4-5"
    }
    """

    func testDecodeBackendResponse() throws {
        let data = try XCTUnwrap(responseJSON.data(using: .utf8))
        let response = try JSONDecoder().decode(WordInfoResponse.self, from: data)

        XCTAssertEqual(response.model, "claude-haiku-4-5")
        let info = response.wordInfo
        XCTAssertEqual(info.senses.count, 2)
        XCTAssertEqual(info.senses[0].meaning, "(事業を)経営する、運営する")
        XCTAssertEqual(info.senses[0].partOfSpeech, "動詞")
        XCTAssertNotNil(info.senses[0].note)
        XCTAssertNil(info.senses[1].note)
        XCTAssertEqual(info.pronunciation.ipa, "/rʌn/")
        XCTAssertNil(info.pronunciation.syllables)
        XCTAssertEqual(info.inflections.count, 2)
        XCTAssertEqual(info.inflections[0].form, "過去形")
        XCTAssertEqual(info.examples.count, 2)
        XCTAssertEqual(info.collocations, ["run a business", "run smoothly"])
        XCTAssertEqual(info.synonyms, ["operate", "manage"])
        XCTAssertEqual(info.antonyms, ["stop"])
        XCTAssertEqual(info.cefrLevel, "A1")
        XCTAssertNil(info.etymology)
        XCTAssertNil(info.register)
        XCTAssertNotNil(info.usageNote)
        XCTAssertNotNil(info.commonMistakes)
    }

    /// SwiftDataに保存した aiInfo が往復（保存→再取得）で保たれること
    func testAIInfoRoundTripsThroughSwiftData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            configurations: config
        )
        let context = ModelContext(container)

        let data = try XCTUnwrap(responseJSON.data(using: .utf8))
        let response = try JSONDecoder().decode(WordInfoResponse.self, from: data)

        let word = Word(text: "run", translation: "経営する")
        word.aiInfo = response.wordInfo
        word.aiInfoStatus = .completed
        word.aiInfoModel = response.model
        word.aiInfoLanguage = "ja"
        context.insert(word)
        try context.save()

        let fetched = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Word>()).first
        )
        XCTAssertEqual(fetched.aiInfoStatus, .completed)
        let info = try XCTUnwrap(fetched.aiInfo)
        XCTAssertEqual(info.senses.first?.meaning, "(事業を)経営する、運営する")
        XCTAssertEqual(info.examples.count, 2)
        XCTAssertEqual(fetched.aiInfoLanguage, "ja")
    }
}

@MainActor
private final class MockWordInfoService: WordInfoService {
    var result: Result<WordInfoResponse, Error> = .failure(BackendAPIError.serverError(statusCode: 500, message: nil))
    var callCount = 0
    var lastWord: String?
    var lastContext: String?
    var lastUserTranslation: String?
    var lastRegenerate: Bool?

    func fetchWordInfo(
        word: String,
        targetLanguage: String,
        context: String?,
        userTranslation: String?,
        regenerate: Bool
    ) async throws -> WordInfoResponse {
        callCount += 1
        lastWord = word
        lastContext = context
        lastUserTranslation = userTranslation
        lastRegenerate = regenerate
        return try result.get()
    }
}

@MainActor
final class WordAIInfoGeneratorTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeResponse() -> WordInfoResponse {
        WordInfoResponse(
            wordInfo: WordAIInfo(
                senses: [
                    .init(meaning: "りんご", englishDefinition: "a round fruit", partOfSpeech: "名詞", note: nil)
                ],
                pronunciation: .init(ipa: "/ˈæp.əl/", syllables: "AP-ple"),
                inflections: [],
                examples: [
                    .init(english: "I ate an apple.", translation: "りんごを食べた。"),
                    .init(english: "Apples are sweet.", translation: "りんごは甘い。"),
                ],
                collocations: [],
                synonyms: [],
                antonyms: [],
                usageNote: nil,
                cefrLevel: "A1",
                etymology: nil,
                register: nil,
                commonMistakes: nil
            ),
            model: "claude-haiku-4-5",
            cached: nil
        )
    }

    func testGenerateSuccessSetsCompleted() async throws {
        let context = try makeContext()
        let word = Word(text: "apple", translation: "りんご")
        context.insert(word)

        let service = MockWordInfoService()
        service.result = .success(makeResponse())
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        XCTAssertEqual(word.aiInfoStatus, .completed)
        XCTAssertEqual(word.aiInfo?.senses.first?.meaning, "りんご")
        XCTAssertEqual(word.aiInfoModel, "claude-haiku-4-5")
        XCTAssertNotNil(word.aiInfoGeneratedAt)
        XCTAssertNotNil(word.aiInfoLanguage)
        XCTAssertEqual(service.lastWord, "apple")
        XCTAssertEqual(service.lastUserTranslation, "りんご")
    }

    func testGenerateFailureSetsFailed() async throws {
        let context = try makeContext()
        let word = Word(text: "apple", translation: "りんご")
        context.insert(word)

        let service = MockWordInfoService()
        service.result = .failure(BackendAPIError.serverError(statusCode: 500, message: nil))
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        XCTAssertEqual(word.aiInfoStatus, .failed)
        XCTAssertNil(word.aiInfo)
        XCTAssertNil(word.aiInfoGeneratedAt)
    }

    /// 401（API Secret未設定・不一致）の失敗時に、Settings確認を促すメッセージが保存され、
    /// 再生成の成功でクリアされること
    func testGenerateUnauthorizedStoresErrorMessage() async throws {
        let context = try makeContext()
        let word = Word(text: "apple", translation: "りんご")
        context.insert(word)

        let service = MockWordInfoService()
        service.result = .failure(BackendAPIError.unauthorized)
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        XCTAssertEqual(word.aiInfoStatus, .failed)
        let message = try XCTUnwrap(word.aiInfoErrorMessage)
        XCTAssertTrue(message.contains("API Secret"))

        service.result = .success(makeResponse())
        await generator.generate(for: word)

        XCTAssertEqual(word.aiInfoStatus, .completed)
        XCTAssertNil(word.aiInfoErrorMessage)
    }

    func testGenerateSkipsWhenAlreadyGenerating() async throws {
        let context = try makeContext()
        let word = Word(text: "apple", translation: "りんご")
        word.aiInfoStatus = .generating
        context.insert(word)

        let service = MockWordInfoService()
        service.result = .success(makeResponse())
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        XCTAssertEqual(service.callCount, 0)
        XCTAssertEqual(word.aiInfoStatus, .generating)
    }

    /// 訳語が空（見出し語のみで登録）の場合、生成成功時に先頭語義の母語訳で自動補完されること
    func testGenerateFillsEmptyTranslation() async throws {
        let context = try makeContext()
        let word = Word(text: "apple", translation: "")
        context.insert(word)

        let service = MockWordInfoService()
        service.result = .success(makeResponse())
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        XCTAssertEqual(word.translation, "りんご")
        // 空の訳語はAPIへのヒントとしては送らない
        XCTAssertNil(service.lastUserTranslation)
    }

    /// ユーザーが入力済みの訳語は生成結果で上書きしないこと
    func testGenerateKeepsExistingTranslation() async throws {
        let context = try makeContext()
        let word = Word(text: "apple", translation: "アップル")
        context.insert(word)

        let service = MockWordInfoService()
        service.result = .success(makeResponse())
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        XCTAssertEqual(word.translation, "アップル")
    }

    /// 出現記録に sourcePhoto がある場合、そのOCR本文が文脈として渡ること
    func testGeneratePassesOCRContext() async throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Lesson 1")
        let photo = Photo(lesson: lesson, imageFileName: "page.jpg")
        photo.ocrText = "My uncle runs a small bakery."
        let word = Word(text: "run", translation: "経営する")
        let occurrence = WordOccurrence(word: word, lesson: lesson, sourcePhoto: photo)
        context.insert(schoolClass)
        context.insert(lesson)
        context.insert(photo)
        context.insert(word)
        context.insert(occurrence)

        let service = MockWordInfoService()
        service.result = .success(makeResponse())
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        XCTAssertEqual(service.lastContext, "My uncle runs a small bakery.")
    }
}
