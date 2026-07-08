import Foundation
import SwiftData
import Testing
@testable import ESLLearningAssistant

/// `DocumentFileImporter.importFiles`（取り込み → `Document` 化）と
/// `ModelContext.deleteDocument`（原本削除＋出現の `sourceDocument` nullify）を検証する。
/// 取り込みは実 URL を要するため一時ファイルを作って渡し、`DocumentStorage` に書かれた原本は
/// 作成された `Document.documentFileName` を辿って個別に掃除する。
@MainActor
struct DocumentImportAndDeleteTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            AudioClip.self, Document.self,
            configurations: config
        )
        return ModelContext(container)
    }

    /// 一時ディレクトリに（ファイル名から導く title を汚さないよう）一意なサブフォルダを掘り、
    /// 素のファイル名で書いてその URL を返す。
    private func writeTempFile(name: String, contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func cleanUpStorage(_ documents: [Document]) {
        for document in documents {
            DocumentStorage.delete(fileName: document.documentFileName)
        }
    }

    @Test func importsSupportedFilesAndSkipsUnsupported() throws {
        let context = try makeContext()
        let pdf = try writeTempFile(name: "handout.pdf", contents: "%PDF-1.4 sample")
        let docx = try writeTempFile(name: "notes.docx", contents: "docx sample bytes")
        let txt = try writeTempFile(name: "readme.txt", contents: "unsupported")
        defer { for url in [pdf, docx, txt] { try? FileManager.default.removeItem(at: url) } }

        let count = DocumentFileImporter.importFiles([pdf, docx, txt], into: nil, context: context)

        let documents = try context.fetch(FetchDescriptor<Document>())
        defer { cleanUpStorage(documents) }

        #expect(count == 2) // .txt はスキップ
        #expect(documents.count == 2)
        #expect(Set(documents.map(\.fileKind)) == [.pdf, .docx])
        #expect(Set(documents.map(\.title)) == ["handout", "notes"]) // 拡張子を除いたファイル名
        #expect(documents.allSatisfy { $0.processingStatus == .pending }) // 取り込みは pending のみ
        #expect(documents.allSatisfy { $0.byteSize > 0 })
        #expect(documents.allSatisfy { $0.lessons.isEmpty }) // レッスン未指定＝ライブラリ文書
    }

    @Test func importLinksDocumentToLesson() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Lesson 1")
        context.insert(schoolClass)
        context.insert(lesson)
        try context.save()

        let pdf = try writeTempFile(name: "handout.pdf", contents: "%PDF-1.4 sample")
        defer { try? FileManager.default.removeItem(at: pdf) }

        let count = DocumentFileImporter.importFiles([pdf], into: lesson, context: context)

        let documents = try context.fetch(FetchDescriptor<Document>())
        defer { cleanUpStorage(documents) }

        #expect(count == 1)
        let document = try #require(documents.first)
        #expect(document.lessons.map(\.id) == [lesson.id])
        #expect(lesson.documents.map(\.id) == [document.id]) // inverse も張られる
    }

    @Test func importReturnsZeroWhenAllUnsupported() throws {
        let context = try makeContext()
        let txt = try writeTempFile(name: "readme.txt", contents: "unsupported")
        defer { try? FileManager.default.removeItem(at: txt) }

        let count = DocumentFileImporter.importFiles([txt], into: nil, context: context)

        #expect(count == 0)
        #expect(try context.fetch(FetchDescriptor<Document>()).isEmpty)
    }

    @Test func deleteDocumentNullifiesSourceDocumentAndKeepsOccurrence() throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Lesson 1")
        let word = Word(text: "apple", translation: "りんご")
        // 実ファイルは不要（deleteDocument の DocumentStorage.delete は try? で無害）。
        let document = Document(title: "Doc", documentFileName: "\(UUID().uuidString).pdf", fileKind: .pdf)
        let fromDocument = WordOccurrence(word: word, lesson: lesson, sourceDocument: document)
        let manual = WordOccurrence(word: word, lesson: lesson) // 出典なし（無関係な出現）

        for model in [schoolClass, lesson, word, document, fromDocument, manual] as [any PersistentModel] {
            context.insert(model)
        }
        try context.save()

        context.deleteDocument(document)

        #expect(try context.fetch(FetchDescriptor<Document>()).isEmpty) // 文書本体は消える
        let occurrences = try context.fetch(FetchDescriptor<WordOccurrence>())
        #expect(occurrences.count == 2) // 出現は両方残る
        #expect(occurrences.allSatisfy { $0.sourceDocument == nil }) // 参照は nullify
        #expect(try context.fetch(FetchDescriptor<Word>()).count == 1) // 単語も残る
    }
}
