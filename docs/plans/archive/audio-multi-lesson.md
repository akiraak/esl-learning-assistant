# Audio詳細画面で複数レッスンへの追加に対応する

## 目的・背景

単語詳細画面（`WordDetailView`）の「Appears in Lessons」では、1つの単語を複数レッスンに
紐付け・一覧表示・個別解除・追加ができる。Audio詳細画面（`AudioDetailView`）は現状
`AudioClip.lesson: Lesson?`（to-one）で **1レッスンのみ** の割当なので、同じく
**複数レッスンへの追加** に対応させる。

## 対応方針

単語は per-occurrence メタ（`occurredAt` / `sourcePhoto`）が要るため join エンティティ
`WordOccurrence` を挟むが、Audio にはそのメタが不要なので **直接の多対多**
（`AudioClip.lessons: [Lesson]` ↔ `Lesson.audioClips`）にする。join エンティティは作らない。

### 変更点

1. **モデル (`AudioClip` / `Lesson`)**
   - `AudioClip.lesson: Lesson?` → `AudioClip.lessons: [Lesson]`
   - `Lesson.audioClips` の inverse を `\AudioClip.lessons` に変更し、delete rule を
     `.cascade` → `.nullify` にする（レッスン削除で音声実体を消さない。音声は
     ライブラリ資産として残る＝Word がレッスン削除で消えないのと同じ思想）。

2. **`AudioDetailView`**
   - 単一 Picker の "Lesson" セクションを、単語画面と同型の "Lessons" セクションに置換：
     linked レッスンを一覧（クラス名サブタイトル付き）＋スワイプで個別解除＋
     "Add to Lesson" ボタンで選択シートを開く。

3. **選択シート**
   - `WordLessonPickerView` を汎用ピッカーとして再利用（文言を単語非依存に微修正、
     既存アクセシビリティ ID は維持）。既にリンク済みのレッスンは除外して二重を防ぐ。

4. **取り込み経路 (`AudioFileImporter` / `AudioImportLessonView` / `AudioView`)**
   - 取り込み時の単一レッスン割当はそのまま（0 or 1）。`clip.lesson = x` を
     `clip.lessons = x.map { [$0] } ?? []` 相当に置換。

5. **一覧行 (`AudioClipRow`)**
   - `clip.lesson` 参照を `clip.lessons` に変更。複数時は先頭＋ "+N" 表記。

6. **`DebugDataCleaner.deleteClass`**
   - AudioClip が cascade されなくなるため、音声ファイルの巻き込み削除を撤去
     （nullify で生き残るクリップのファイルを消すと壊れるため）。コメント更新。

## 影響範囲

- 上記 Swift ファイル群。新規エンティティ追加は無し（ModelContainer 登録は変更不要）。
- **マイグレーション**: to-one → to-many はライトウェイトマイグレーション対応範囲。
  `lesson`→`lessons` のリネームはインファレンス上「削除＋追加」扱いになるため、
  既存の単一リンクは移行されず落ちる可能性がある（ストアは開ける／クラッシュはしない）。
  個人利用アプリのため許容し、必要なら再割当してもらう。失敗時は既存の
  `StoreLoadErrorView` で可視化される。

## テスト方針

- ビルド（`xcodegen generate` → `xcodebuild` / Xcode）で型・スキーマ整合を確認。
- 手動: 音声詳細で複数レッスン追加→一覧反映→スワイプ解除→レッスン削除で音声が
  残ることを確認。
