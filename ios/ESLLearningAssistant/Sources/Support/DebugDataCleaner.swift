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

    /// 指定したClassだけを削除する。cascadeでLesson → Photo / WordOccurrenceも消える。
    static func deleteClass(_ schoolClass: Class, context: ModelContext) throws {
        // エンティティ削除後はリレーションを辿れないため、画像ファイル名を先に集める
        let fileNames = schoolClass.lessons.flatMap(\.photos).map(\.imageFileName)
        context.delete(schoolClass)
        try context.save()
        for fileName in fileNames {
            PhotoStorage.delete(fileName: fileName)
        }
    }

    /// 全Wordを削除する。cascadeでWordOccurrenceも消える。
    static func deleteAllWords(context: ModelContext) throws {
        let words = try context.fetch(FetchDescriptor<Word>())
        for word in words {
            context.delete(word)
        }
        try context.save()
        // イラストはSwiftData管理外のファイルなのでcascadeでは消えない。全Word削除に合わせて
        // ディレクトリごと消す（deleteAllClasses が PhotoStorage.deleteAll() で画像を消すのと同様）
        WordIllustrationStore.removeAll()
    }
}
