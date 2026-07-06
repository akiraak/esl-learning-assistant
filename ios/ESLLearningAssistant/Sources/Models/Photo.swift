import Foundation
import SwiftData

enum PhotoProcessingStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}

@Model
final class Photo {
    var id: UUID
    var lesson: Lesson
    var imageFileName: String
    var capturedAt: Date
    var processingStatus: PhotoProcessingStatus
    /// OCR・翻訳が失敗したときのユーザー向けメッセージ（401時のAPI Secret案内など）。
    /// optional追加のみなので既存データの軽量マイグレーションを維持する。
    var processingErrorMessage: String?
    var ocrText: String?
    var translatedText: String?
    var translationLanguage: String?

    init(
        id: UUID = UUID(),
        lesson: Lesson,
        imageFileName: String,
        capturedAt: Date = .now,
        processingStatus: PhotoProcessingStatus = .pending,
        ocrText: String? = nil,
        translatedText: String? = nil,
        translationLanguage: String? = nil
    ) {
        self.id = id
        self.lesson = lesson
        self.imageFileName = imageFileName
        self.capturedAt = capturedAt
        self.processingStatus = processingStatus
        self.ocrText = ocrText
        self.translatedText = translatedText
        self.translationLanguage = translationLanguage
    }
}

extension Photo {
    /// 一覧表示用のタイトル。OCR結果（Markdown）の最初の見出し（#…）を返し、
    /// 見出しが無ければ最初の非空行を返す。本文が無い（OCR未完了など）場合は空文字。
    var contentTitle: String {
        guard let text = ocrText, !text.isEmpty else { return "" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // 最初の見出し行を優先する
        for line in lines {
            if let heading = Self.headingText(line) {
                return heading
            }
        }
        // 見出しが無ければ最初の非空行を整形して返す
        for line in lines where !line.isEmpty {
            return Self.stripInlineMarkdown(line)
        }
        return ""
    }

    /// `#`〜`######` の見出し行なら本文（整形済み）を返す。見出しでなければ nil。
    private static func headingText(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let body = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        return stripInlineMarkdown(body)
    }

    /// インラインのMarkdown記法（強調・箇条書きマーカー）を取り除く。
    private static func stripInlineMarkdown(_ text: String) -> String {
        var result = text
        // 先頭の箇条書きマーカーを除去
        for bullet in ["- ", "* ", "+ "] where result.hasPrefix(bullet) {
            result.removeFirst(bullet.count)
            break
        }
        // 強調・コードのマーカーを除去
        for token in ["**", "__", "*", "_", "`"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

extension ModelContext {
    /// 写真を削除する。画像ファイル・SwiftData の Photo を消し、
    /// この写真を出典に持つ単語出現（WordOccurrence）の sourcePhoto は
    /// ダングリング参照を避けるため nil 化する（出現自体は残す）。
    func deletePhoto(_ photo: Photo) {
        for occurrence in photo.lesson.wordOccurrences where occurrence.sourcePhoto?.id == photo.id {
            occurrence.sourcePhoto = nil
        }
        PhotoStorage.delete(fileName: photo.imageFileName)
        delete(photo)
        saveOrLog()
    }
}
