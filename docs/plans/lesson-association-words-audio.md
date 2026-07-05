# レッスンとの関連付け（単語・音声）

## 目的・背景

単語・音声（AudioClip）とレッスンの紐付けを、後からユーザーが自由に編集できるようにする。
現状は以下の非対称がある。

- **単語**: レッスンとの関連は `WordOccurrence`（word ↔ lesson の多対多）で表現。登録時（`WordAddView` / 英文タップ）にしか紐付けできず、単語詳細（`WordDetailView`）の「Appears in Lessons」は**閲覧のみ**。後から別レッスンに追加したり外したりできない。
- **音声**: `AudioClip.lesson` は**任意の to-one**。`AudioClipEditView` で割り当て・変更・解除はできるが、
  - Audioタブの「＋」取り込みはレッスン未指定（`into: nil`）で固定。
  - 一覧タップは再生のみで詳細画面が無い。

これを解消し、「登録後もレッスン紐付けを管理できる」体験に揃える。

## 対応方針（全体）

新規 SwiftData エンティティは追加しない（`WordOccurrence` / `AudioClip.lesson` の既存モデルで足りる）。
既存の再生（`TTSPlaybackService` / `TTSPlayerBar`）・レッスンPicker（`AudioClipEditView` / `WordAddView`）のパターンを踏襲する。

---

## Phase 1: 単語詳細からのレッスン管理（追加・削除・編集）

`WordDetailView` の「Appears in Lessons」セクションを編集可能にする。単語は多対多なので
「複数レッスンの集合を管理する」形になる。

### 変更点

- **追加**: セクション末尾に「Add to Lesson」行を置き、タップで `WordLessonPickerView`（新規, sheet）を表示。
  未リンクのレッスンのみ一覧（`class / lesson` 表記、`WordAddView` のネストPicker流用）。選択で `WordOccurrence` を作成（`sourcePhoto = nil`）。
- **削除**: occurrence 行をスワイプ削除。該当 `WordOccurrence` のみ `modelContext.delete`（`Word` 本体・`Lesson` は消えない）。
- **編集**: occurrence 行タップで「別レッスンへ付け替え」を同 Picker で行う（既リンク先は除外）。`sourcePhoto` は素性メタなので保持。

### 重複防止

手動リンクは「そのレッスンに既に出現があるか」を `lesson.id` のみで判定して除外する
（OCR由来の `sourcePhoto != nil` 出現があっても、同一レッスン行が二重に出ないように Picker 側で `linkedLessonIDs` を除外）。

### 実装

- `WordRegistrar` に手動リンク用ヘルパを追加（`link` の集合追加・`lesson.wordOccurrences.append`・`saveOrLog` を再利用）。
  - 例: `static func linkManually(_ word:to:in:)` / 解除は `modelContext.delete(occurrence)` + `saveOrLog`。
- 新規 `Views/WordLessonPickerView.swift`（追加/付け替え兼用。除外IDを受け取る）。
- `WordDetailView` の「Appears in Lessons」セクションに Add 行・スワイプ削除・行タップ編集を追加。
- a11y identifier: `wordAddToLessonButton` など（UIテスト用）。

---

## Phase 2: Audio取り込み時のレッスン関連付け

Audioタブ「＋」は、**先にファイルを選び、後からレッスンを選ぶ**フローにする。

### フロー

1. 「＋」（および空状態の「Import Audio」）で `.fileImporter` を直接提示（現状どおり）。
2. ファイル選択成功で、選ばれた `[URL]` を state に保持し、レッスン選択 sheet（新規 `AudioImportLessonView`）を提示。
3. sheet でレッスンを選び（既定 None）確定すると、そのレッスンへ `AudioFileImporter.importFiles(urls, into: lesson)` を実行し dismiss。Cancel で取り込み中止。

### 変更点

- 新規 `Views/AudioImportLessonView.swift`（sheet）: レッスン Picker（既定 None、`AudioClipEditView` 流用）＋ Import / Cancel。取り込む `[URL]` を受け取る。
- `AudioView`: `.fileImporter` 成功時は即取り込まず `pendingImportURLs` に退避 → sheet 提示。取り込み実行と失敗アラートはこのフローに合わせて移動。

### 注意（セキュリティスコープ）

`.fileImporter` の URL はセキュリティスコープ付き。sheet を挟んで後から読むため、実際に読む取り込み時に
`startAccessingSecurityScopedResource()` を呼ぶ（`AudioFileImporter` は既にURL単位で start/stop 済み）。
sheet 提示中にスコープが失われて読めない場合は、ファイル選択直後に一旦データを取り込み（レッスン None）→
確定時にレッスンを付け替える方式へフォールバックする（実装時に実機で確認）。

`AudioFileImporter.importFiles(_:into:context:)` は既に `lesson` 引数を持つため、取り込みロジック自体は変更不要。

---

## Phase 3: Audio詳細画面＋一覧タップで再生＆遷移

### 3a. AudioDetailView（新規）

`Views/AudioDetailView.swift`。`AudioView` から共有の `TTSPlaybackService` を受け取る（画面遷移後も
下部 `TTSPlayerBar` が継続表示されるよう、再生状態は一元管理）。

- **再生**: この clip がアクティブなら再生/一時停止、そうでなければこの clip を再生する大きめのボタン。
  下部の `TTSPlayerBar` は `NavigationStack` の `safeAreaInset` にあるので push 後も継続表示。
- **レッスンの追加・削除・編集**: `AudioClip.lesson` は to-one なので Picker（None＝削除 / 選択＝追加・変更）で全て賄う。`AudioClipEditView` のPickerを inline 化。
- **タイトル編集**: `TextField` で inline 編集。
- **削除**: 音声本体削除（`AudioStorage.delete` + `modelContext.delete` + `saveOrLog`。再生中なら停止）。

### 3b. 一覧タップ＝再生＋遷移

`AudioView` の行を `NavigationLink { AudioDetailView(clip:, playback:) }` にし、
`.simultaneousGesture(TapGesture().onEnded { togglePlay(clip) })` で**遷移と再生を同時実行**。

- 行内の再生/停止ボタンは残す（明示操作用）。
- contextMenu は Delete のみ残す（Edit は詳細画面に集約 → `AudioClipEditView` は詳細から使うか、廃止を検討）。
- push では `AudioView` の `NavigationStack` は消えないため `onDisappear { playback.stop() }` は発火せず再生継続。タブ離脱時のみ停止。

---

## 影響範囲

- 変更: `WordDetailView.swift`, `WordRegistrar.swift`, `AudioView.swift`
- 新規: `WordLessonPickerView.swift`, `AudioImportView.swift`, `AudioDetailView.swift`
- 既存 `AudioClipEditView.swift` は詳細へ機能移行（残置 or 廃止を実装時判断）
- **SwiftData エンティティ追加なし** → ModelContainer 登録・マイグレーション変更は不要
- 新規 `.swift` は `ios/project.yml` がフォルダ glob のため `cd ios && xcodegen generate` で取り込む

## テスト方針

- ビルド: `xcodegen generate` 後にビルドが通ること。
- 手動確認:
  - 単語詳細: レッスン追加→行表示、スワイプ削除、行タップ付け替え、既リンク先が Picker に出ないこと。
  - Audio取り込み: ＋→レッスン選択→ファイル選択→そのレッスンに紐付いて一覧表示。None でも取り込めること。
  - Audio詳細: 一覧タップで再生開始＋詳細遷移が同時に起きること。詳細でのレッスン変更/解除・タイトル編集・削除。
  - 遷移後も下部プレイヤーが継続し、タブを離れると停止すること。
- 既存 UITest（`ESLLearningAssistantUITests`）が壊れないこと。行タップ挙動変更に注意。
```
