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
    /// senseHint == nil（主見出し）のときの応答
    var result: Result<WordInfoResponse, Error> = .failure(BackendAPIError.serverError(statusCode: 500, message: nil))
    /// senseHint 付き（別見出し）の応答。hint 文字列 → 応答
    var siblingResults: [String: Result<WordInfoResponse, Error>] = [:]
    var callCount = 0
    var lastWord: String?
    var lastContext: String?
    var lastUserTranslation: String?
    var lastRegenerate: Bool?
    var seenSenseHints: [String] = []

    func fetchWordInfo(
        word: String,
        targetLanguage: String,
        context: String?,
        userTranslation: String?,
        regenerate: Bool,
        senseHint: String?
    ) async throws -> WordInfoResponse {
        callCount += 1
        lastWord = word
        lastRegenerate = regenerate
        if let senseHint {
            seenSenseHints.append(senseHint)
            return try (siblingResults[senseHint] ?? result).get()
        }
        lastContext = context
        lastUserTranslation = userTranslation
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

    // MARK: - 多義語の辞書式分割（見出しごとに個別生成）

    /// 1見出し分の生成結果を作る。otherHomographs を渡すと分割トリガになる。
    private func makeInfo(
        meaning: String,
        definition: String,
        partOfSpeech: String,
        otherHomographs: [WordAIInfo.Homograph] = []
    ) -> WordInfoResponse {
        WordInfoResponse(
            wordInfo: WordAIInfo(
                senses: [.init(meaning: meaning, englishDefinition: definition, partOfSpeech: partOfSpeech, note: nil)],
                otherHomographs: otherHomographs,
                pronunciation: .init(ipa: "/fɔːl/", syllables: nil),
                inflections: [.init(form: "past tense", text: "\(meaning)-past")],
                examples: [.init(english: "Example of \(meaning).", translation: "\(meaning)の例。")],
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

    /// 別見出し（otherHomographs）があると、見出しごとに個別生成して兄弟 Word に分割する。
    /// 各エントリは自分の意味専用の内容（senses/活用/例文）を持つ。
    func testGenerateSplitsHomographsIntoSiblingWords() async throws {
        let context = try makeContext()
        let word = Word(text: "fall", translation: "")
        context.insert(word)

        let service = MockWordInfoService()
        // 主見出し = 落ちる（別見出しに 秋 を挙げる）
        service.result = .success(makeInfo(
            meaning: "落ちる", definition: "to drop down", partOfSpeech: "動詞",
            otherHomographs: [.init(meaning: "秋", partOfSpeech: "名詞")]
        ))
        // 別見出し「秋（名詞）」の個別生成結果
        service.siblingResults["秋（名詞）"] = .success(makeInfo(
            meaning: "秋", definition: "the season after summer", partOfSpeech: "名詞"
        ))
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        // 主見出し（落ちる）
        XCTAssertEqual(word.translation, "落ちる")
        XCTAssertNil(word.senseGroupKey)
        XCTAssertEqual(word.aiInfo?.senses.map(\.meaning), ["落ちる"])
        XCTAssertEqual(word.illustrationSenseIndex, 0)
        XCTAssertEqual(service.seenSenseHints, ["秋（名詞）"])

        // 兄弟見出し（秋）— 内容が独立している（活用・例文が秋のもの）
        let all = try context.fetch(FetchDescriptor<Word>())
        XCTAssertEqual(all.count, 2)
        let sibling = try XCTUnwrap(all.first { $0.id != word.id })
        XCTAssertEqual(sibling.text, "fall")
        XCTAssertEqual(sibling.translation, "秋")
        XCTAssertEqual(sibling.senseGroupKey, "1")
        XCTAssertEqual(sibling.aiInfo?.senses.map(\.meaning), ["秋"])
        XCTAssertEqual(sibling.aiInfo?.inflections.first?.text, "秋-past")
        XCTAssertEqual(sibling.aiInfo?.examples.first?.english, "Example of 秋.")
        XCTAssertEqual(sibling.illustrationSenseIndex, 1)
        XCTAssertEqual(sibling.aiInfoStatus, .completed)
    }

    /// 別見出しが無ければ分割せず、senseHint 付きの追加生成もしない
    func testGenerateDoesNotSplitSingleHeadword() async throws {
        let context = try makeContext()
        let word = Word(text: "apple", translation: "")
        context.insert(word)

        let service = MockWordInfoService()
        service.result = .success(makeResponse())
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)

        XCTAssertNil(word.senseGroupKey)
        XCTAssertTrue(service.seenSenseHints.isEmpty)
        let all = try context.fetch(FetchDescriptor<Word>())
        XCTAssertEqual(all.count, 1)
    }

    /// 再生成しても兄弟 Word を重複生成せず、既存の兄弟を更新する
    func testGenerateUpdatesExistingSiblingOnRerun() async throws {
        let context = try makeContext()
        let word = Word(text: "fall", translation: "")
        context.insert(word)

        let service = MockWordInfoService()
        service.result = .success(makeInfo(
            meaning: "落ちる", definition: "to drop down", partOfSpeech: "動詞",
            otherHomographs: [.init(meaning: "秋", partOfSpeech: "名詞")]
        ))
        service.siblingResults["秋（名詞）"] = .success(makeInfo(
            meaning: "秋", definition: "the season after summer", partOfSpeech: "名詞"
        ))
        let generator = WordAIInfoGenerator(service: service)

        await generator.generate(for: word)
        await generator.generate(for: word, regenerate: true)

        let all = try context.fetch(FetchDescriptor<Word>())
        XCTAssertEqual(all.count, 2)  // 兄弟は1つのまま（更新される）
        let siblings = all.filter { $0.senseGroupKey == "1" }
        XCTAssertEqual(siblings.count, 1)
    }
}
