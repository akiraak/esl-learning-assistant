import Foundation
import SwiftData

@Model
final class WordOccurrence {
    var id: UUID
    var word: Word
    var lesson: Lesson
    var sourcePhoto: Photo?
    /// タップ登録元の音声クリップ（文字起こし英文からの登録時）。`sourcePhoto` の音声版で、
    /// AI 単語情報生成に transcript を文脈として渡すために保持する。手動/写真登録では nil。
    /// optional 追加のみなので既存ストアの軽量マイグレーションを維持する（`sourcePhoto` と同様、
    /// 逆リレーションは張らず、クリップ削除時に `ModelContext.deleteAudioClip(_:)` で nullify する）。
    var sourceAudio: AudioClip?
    /// タップ登録元の文書（抽出英文からの登録時）。`sourceAudio` の文書版で、
    /// AI 単語情報生成に抽出テキストを文脈として渡すために保持する。手動/写真/音声登録では nil。
    /// optional 追加のみなので既存ストアの軽量マイグレーションを維持する（`sourceAudio` と同様、
    /// 逆リレーションは張らず、文書削除時に `ModelContext.deleteDocument(_:)` で nullify する）。
    var sourceDocument: Document?
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        word: Word,
        lesson: Lesson,
        sourcePhoto: Photo? = nil,
        sourceAudio: AudioClip? = nil,
        sourceDocument: Document? = nil,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.word = word
        self.lesson = lesson
        self.sourcePhoto = sourcePhoto
        self.sourceAudio = sourceAudio
        self.sourceDocument = sourceDocument
        self.occurredAt = occurredAt
    }
}
