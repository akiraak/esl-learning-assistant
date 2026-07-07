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
}
