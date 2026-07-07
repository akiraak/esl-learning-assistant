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
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        word: Word,
        lesson: Lesson,
        sourcePhoto: Photo? = nil,
        sourceAudio: AudioClip? = nil,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.word = word
        self.lesson = lesson
        self.sourcePhoto = sourcePhoto
        self.sourceAudio = sourceAudio
        self.occurredAt = occurredAt
    }
}
