import SwiftData
import Testing
@testable import ESLLearningAssistant

/// `WordRegistrar` の登録ロジック（再利用/新規作成・出現記録の紐付けと重複ガード・AI生成トリガ）を検証する。
/// AI生成トリガはネットワークを叩かないよう `generateAIInfo` を注入して観測する。
@MainActor
struct WordRegistrarTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, AudioClip.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func allWords(_ context: ModelContext) throws -> [Word] {
        try context.fetch(FetchDescriptor<Word>())
    }

    @Test func createsNewWordAndTriggersAIInfo() throws {
        let context = try makeContext()
        var generated: [String] = []

        let result = WordRegistrar.register(
            text: "apple",
            in: context,
            existingWords: try allWords(context),
            generateAIInfo: { generated.append($0.text) }
        )

        let unwrapped = try #require(result)
        #expect(unwrapped.isNew)
        #expect(unwrapped.word.text == "apple")
        #expect(try allWords(context).count == 1)
        #expect(generated == ["apple"])
    }

    @Test func reusesExistingWordCaseInsensitively() throws {
        let context = try makeContext()
        let existing = Word(text: "Apple", translation: "りんご")
        context.insert(existing)
        try context.save()
        var generated: [String] = []

        let result = WordRegistrar.register(
            text: "apple",
            in: context,
            existingWords: try allWords(context),
            generateAIInfo: { generated.append($0.text) }
        )

        let unwrapped = try #require(result)
        #expect(!unwrapped.isNew)
        #expect(unwrapped.word.id == existing.id)
        #expect(try allWords(context).count == 1)
        // 既に aiInfoStatus が none のままなので生成はトリガされる（未生成語の再利用）
        #expect(generated == ["Apple"])
    }

    @Test func doesNotTriggerAIInfoWhenAlreadyCompleted() throws {
        let context = try makeContext()
        let existing = Word(text: "apple", translation: "りんご")
        existing.aiInfoStatus = .completed
        context.insert(existing)
        try context.save()
        var generated: [String] = []

        _ = WordRegistrar.register(
            text: "apple",
            in: context,
            existingWords: try allWords(context),
            generateAIInfo: { generated.append($0.text) }
        )

        #expect(generated.isEmpty)
    }

    @Test func linksOccurrenceToLessonWithSourcePhoto() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1")
        let photo = Photo(lesson: lesson, imageFileName: "page.jpg")
        context.insert(schoolClass)
        context.insert(lesson)
        context.insert(photo)

        let result = WordRegistrar.register(
            text: "apple",
            in: context,
            existingWords: try allWords(context),
            lesson: lesson,
            sourcePhoto: photo,
            generateAIInfo: { _ in }
        )

        let word = try #require(result).word
        #expect(word.occurrences.count == 1)
        #expect(word.occurrences.first?.lesson.id == lesson.id)
        #expect(word.occurrences.first?.sourcePhoto?.id == photo.id)
        #expect(lesson.wordOccurrences.contains { $0.word.id == word.id })
    }

    @Test func doesNotDuplicateOccurrenceForSameWordAndPhoto() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1")
        let photo = Photo(lesson: lesson, imageFileName: "page.jpg")
        context.insert(schoolClass)
        context.insert(lesson)
        context.insert(photo)

        for _ in 0..<2 {
            _ = WordRegistrar.register(
                text: "apple",
                in: context,
                existingWords: try allWords(context),
                lesson: lesson,
                sourcePhoto: photo,
                generateAIInfo: { _ in }
            )
        }

        let word = try #require(try allWords(context).first)
        #expect(word.occurrences.count == 1)
    }

    @Test func linksOccurrenceToLessonWithSourceAudio() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1")
        let clip = AudioClip(title: "Dialogue", audioFileName: "clip.wav")
        context.insert(schoolClass)
        context.insert(lesson)
        context.insert(clip)

        let result = WordRegistrar.register(
            text: "apple",
            in: context,
            existingWords: try allWords(context),
            lesson: lesson,
            sourceAudio: clip,
            generateAIInfo: { _ in }
        )

        let word = try #require(result).word
        #expect(word.occurrences.count == 1)
        #expect(word.occurrences.first?.lesson.id == lesson.id)
        #expect(word.occurrences.first?.sourceAudio?.id == clip.id)
        #expect(word.occurrences.first?.sourcePhoto == nil)
        #expect(lesson.wordOccurrences.contains { $0.word.id == word.id })
    }

    @Test func doesNotDuplicateOccurrenceForSameWordAndAudio() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1")
        let clip = AudioClip(title: "Dialogue", audioFileName: "clip.wav")
        context.insert(schoolClass)
        context.insert(lesson)
        context.insert(clip)

        for _ in 0..<2 {
            _ = WordRegistrar.register(
                text: "apple",
                in: context,
                existingWords: try allWords(context),
                lesson: lesson,
                sourceAudio: clip,
                generateAIInfo: { _ in }
            )
        }

        let word = try #require(try allWords(context).first)
        #expect(word.occurrences.count == 1)
    }

    /// 音声クリップ削除時に、その音声を出典に持つ出現の `sourceAudio` が nil 化され
    /// （ダングリング参照を避ける）、出現自体は残ることを検証する。
    @Test func deletingAudioClipNullifiesSourceAudioButKeepsOccurrence() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Unit 1")
        let clip = AudioClip(title: "Dialogue", audioFileName: "clip.wav")
        context.insert(schoolClass)
        context.insert(lesson)
        context.insert(clip)

        let word = try #require(WordRegistrar.register(
            text: "apple",
            in: context,
            existingWords: try allWords(context),
            lesson: lesson,
            sourceAudio: clip,
            generateAIInfo: { _ in }
        )).word
        #expect(word.occurrences.first?.sourceAudio?.id == clip.id)

        context.deleteAudioClip(clip)

        let occurrences = try context.fetch(FetchDescriptor<WordOccurrence>())
        #expect(occurrences.count == 1)
        #expect(occurrences.first?.sourceAudio == nil)
        #expect(try context.fetch(FetchDescriptor<AudioClip>()).isEmpty)
    }

    @Test func returnsNilForEmptyText() throws {
        let context = try makeContext()
        let result = WordRegistrar.register(
            text: "   ",
            in: context,
            existingWords: try allWords(context),
            generateAIInfo: { _ in }
        )
        #expect(result == nil)
        #expect(try allWords(context).isEmpty)
    }

    // MARK: - correct（登録済み単語のリネーム／マージ）

    /// レッスンに1回出現する単語を返すヘルパ。
    @discardableResult
    private func makeWord(
        _ text: String,
        translation: String = "",
        in context: ModelContext,
        lesson: Lesson? = nil
    ) -> Word {
        let word = Word(text: text, translation: translation)
        context.insert(word)
        if let lesson {
            let occurrence = WordOccurrence(word: word, lesson: lesson)
            context.insert(occurrence)
            lesson.wordOccurrences.append(occurrence)
        }
        return word
    }

    private func makeLesson(_ title: String, in context: ModelContext) -> Lesson {
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: title)
        context.insert(schoolClass)
        context.insert(lesson)
        return lesson
    }

    /// 衝突が無ければ同じ行の text を差し替え、旧綴り由来の派生情報をクリアして AI 再生成をトリガする。
    /// reviewState と occurrences は保持される。
    @Test func correctRenamesInPlaceWhenNoCollision() throws {
        let context = try makeContext()
        let lesson = makeLesson("Unit 1", in: context)
        let word = makeWord("ran", translation: "走った", in: context, lesson: lesson)
        word.partOfSpeech = "動詞"
        word.aiInfoStatus = .completed
        word.reviewState.masteryPercent = 60
        try context.save()
        var regenerated: [String] = []

        let outcome = WordRegistrar.correct(
            word,
            to: "run",
            in: context,
            existingWords: try allWords(context),
            regenerateAIInfo: { regenerated.append($0.text) }
        )

        guard case .renamedInPlace(let renamed) = try #require(outcome) else {
            Issue.record("expected renamedInPlace")
            return
        }
        #expect(renamed.id == word.id)
        #expect(renamed.text == "run")
        // 旧綴り由来の派生情報はクリアされ、AI 再生成がトリガされる
        #expect(renamed.translation.isEmpty)
        #expect(renamed.partOfSpeech == nil)
        #expect(renamed.aiInfoStatus == .none)
        #expect(regenerated == ["run"])
        // レビュー進捗と出現は保持される（同じ学習対象の綴り訂正）
        #expect(renamed.reviewState.masteryPercent == 60)
        #expect(renamed.occurrences.count == 1)
        #expect(renamed.occurrences.first?.lesson.id == lesson.id)
        #expect(try allWords(context).count == 1)
    }

    /// 正規化形が既存の別単語と一致したら、出現を既存語へ集約して元の行を削除する（マージ）。
    /// 既存語の reviewState・translation は維持され、AI 再生成はしない。
    @Test func correctMergesIntoExistingWordOnCollision() throws {
        let context = try makeContext()
        let lessonA = makeLesson("Unit A", in: context)
        let lessonB = makeLesson("Unit B", in: context)
        let survivor = makeWord("run", translation: "走る", in: context, lesson: lessonA)
        survivor.reviewState.masteryPercent = 80
        let source = makeWord("ran", translation: "走った", in: context, lesson: lessonB)
        try context.save()
        var regenerated: [String] = []

        let outcome = WordRegistrar.correct(
            source,
            to: "run",
            in: context,
            existingWords: try allWords(context),
            regenerateAIInfo: { regenerated.append($0.text) }
        )

        guard case .mergedInto(let merged) = try #require(outcome) else {
            Issue.record("expected mergedInto")
            return
        }
        #expect(merged.id == survivor.id)
        // source は削除され、既存語に両レッスンの出現が集約される
        #expect(try allWords(context).count == 1)
        let lessonIDs = Set(merged.occurrences.map(\.lesson.id))
        #expect(lessonIDs == [lessonA.id, lessonB.id])
        // 既存語の値は維持、AI 再生成はしない
        #expect(merged.translation == "走る")
        #expect(merged.reviewState.masteryPercent == 80)
        #expect(regenerated.isEmpty)
    }

    /// マージ時、既存語に同一レッスンの出現があれば重複を作らず捨てる（dedup）。
    @Test func correctMergeDedupsOccurrenceInSameLesson() throws {
        let context = try makeContext()
        let lesson = makeLesson("Unit 1", in: context)
        let survivor = makeWord("run", in: context, lesson: lesson)
        let source = makeWord("ran", in: context, lesson: lesson)
        try context.save()

        let outcome = WordRegistrar.correct(
            source,
            to: "run",
            in: context,
            existingWords: try allWords(context),
            regenerateAIInfo: { _ in }
        )

        guard case .mergedInto(let merged) = try #require(outcome) else {
            Issue.record("expected mergedInto")
            return
        }
        #expect(merged.occurrences.count == 1)
        #expect(try context.fetch(FetchDescriptor<WordOccurrence>()).count == 1)
        #expect(try allWords(context).count == 1)
    }

    /// 完全一致（訂正不要）は nil を返し、何も変更しない。
    @Test func correctReturnsNilWhenTextUnchanged() throws {
        let context = try makeContext()
        let word = makeWord("run", translation: "走る", in: context)
        word.aiInfoStatus = .completed
        try context.save()
        var regenerated: [String] = []

        let outcome = WordRegistrar.correct(
            word,
            to: "run",
            in: context,
            existingWords: try allWords(context),
            regenerateAIInfo: { regenerated.append($0.text) }
        )

        #expect(outcome == nil)
        #expect(word.translation == "走る")
        #expect(word.aiInfoStatus == .completed)
        #expect(regenerated.isEmpty)
    }

    /// 大小のみの違いは綴り（表示）だけ整え、派生情報・AI情報は保持する（再生成しない）。
    @Test func correctCaseOnlyChangeKeepsDerivedInfo() throws {
        let context = try makeContext()
        let word = makeWord("Apple", translation: "りんご", in: context)
        word.aiInfoStatus = .completed
        try context.save()
        var regenerated: [String] = []

        let outcome = WordRegistrar.correct(
            word,
            to: "apple",
            in: context,
            existingWords: try allWords(context),
            regenerateAIInfo: { regenerated.append($0.text) }
        )

        guard case .renamedInPlace(let renamed) = try #require(outcome) else {
            Issue.record("expected renamedInPlace")
            return
        }
        #expect(renamed.text == "apple")
        // 大小のみの違いなので派生情報は有効なまま
        #expect(renamed.translation == "りんご")
        #expect(renamed.aiInfoStatus == .completed)
        #expect(regenerated.isEmpty)
    }

    /// 空文字の lemma は訂正不要として nil を返す。
    @Test func correctReturnsNilForEmptyLemma() throws {
        let context = try makeContext()
        let word = makeWord("run", in: context)
        try context.save()

        let outcome = WordRegistrar.correct(
            word,
            to: "   ",
            in: context,
            existingWords: try allWords(context),
            regenerateAIInfo: { _ in }
        )
        #expect(outcome == nil)
        #expect(word.text == "run")
    }
}
