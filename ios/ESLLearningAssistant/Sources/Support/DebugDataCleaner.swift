import Foundation
import SwiftData

/// デバッグメニュー用のデータ一括削除。
/// バッチ削除（`context.delete(model:)`）はcascadeルールが適用されないため、
/// 全件フェッチして1件ずつ削除する。
enum DebugDataCleaner {
    /// 全データを削除する（設定値のUserDefaultsは対象外）。
    static func deleteAllData(context: ModelContext) throws {
        try deleteAllClasses(context: context)
        try deleteAllWords(context: context)
        try deleteAllCompositions(context: context)
        try deleteAllAudioClips(context: context)
        try deleteAllDocuments(context: context)
    }

    /// 全Classを削除する。cascadeでLesson → Photo / WordOccurrenceも消える。
    static func deleteAllClasses(context: ModelContext) throws {
        let classes = try context.fetch(FetchDescriptor<Class>())
        for schoolClass in classes {
            context.delete(schoolClass)
        }
        try context.save()
        // 全PhotoはいずれかのLesson配下にあるため、画像ファイルはディレクトリごと削除する
        PhotoStorage.deleteAll()
    }

    /// 指定したClassだけを削除する。cascadeでLesson → Photo / WordOccurrenceが消える。
    /// AudioClip / Document は多対多（nullify）なのでレッスン紐付けが外れるだけで本体は残す
    /// （ライブラリ資産として存続。全消しは deleteAllAudioClips / deleteAllDocuments で行う）。
    static func deleteClass(_ schoolClass: Class, context: ModelContext) throws {
        // エンティティ削除後はリレーションを辿れないため、ファイル名を先に集める
        let photoFileNames = schoolClass.lessons.flatMap(\.photos).map(\.imageFileName)
        context.delete(schoolClass)
        try context.save()
        for fileName in photoFileNames {
            PhotoStorage.delete(fileName: fileName)
        }
    }

    /// 全AudioClipを削除する。実ファイルはディレクトリごと削除する。
    /// （紐付きクリップは deleteAllClasses でも消えるが、レッスン非依存のライブラリ音声も含めて全消しする）
    static func deleteAllAudioClips(context: ModelContext) throws {
        let clips = try context.fetch(FetchDescriptor<AudioClip>())
        for clip in clips {
            context.delete(clip)
        }
        try context.save()
        AudioStorage.deleteAll()
    }

    /// 全Documentを削除する。原本ファイルはディレクトリごと削除する。
    /// （紐付き文書は deleteAllClasses でも消えるが、レッスン非依存のライブラリ文書も含めて全消しする）
    static func deleteAllDocuments(context: ModelContext) throws {
        let documents = try context.fetch(FetchDescriptor<Document>())
        for document in documents {
            context.delete(document)
        }
        try context.save()
        DocumentStorage.deleteAll()
    }

    /// 全Wordを削除する。cascadeでWordOccurrenceも消える。
    static func deleteAllWords(context: ModelContext) throws {
        let words = try context.fetch(FetchDescriptor<Word>())
        for word in words {
            context.delete(word)
        }
        try context.save()
    }

    /// 全Compositionを削除する。
    static func deleteAllCompositions(context: ModelContext) throws {
        let compositions = try context.fetch(FetchDescriptor<Composition>())
        for composition in compositions {
            context.delete(composition)
        }
        try context.save()
    }
}
