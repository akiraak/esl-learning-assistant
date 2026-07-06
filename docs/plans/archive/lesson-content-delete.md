# レッスンのコンテンツ（写真）を削除可能に

## 目的・背景

レッスンの「Content」セクションに追加した写真（`Photo`）を削除する手段が無い。誤って追加した写真や不要になったページを消せるようにする。削除の起点は 2 箇所:

1. **レッスン画面の一覧行の左スワイプ** — `LessonsView` の Content セクションの各 `PhotoRow`。
2. **コンテンツ詳細画面の最下部の delete ボタン** — `PhotoDetailView` の一番下。

## 現状整理（調査結果）

- **一覧**: `LessonsView.lessonContent`（162–221 行）の Content セクション。`ForEach(photos)` で `Button { selectedPhoto = photo } label: { PhotoRow(photo:) }`。単語行は既に `.swipeActions(edge: .trailing)` で「Remove」を実装済み（247–253 行）＝同型で追加できる。
- **詳細**: `PhotoDetailView`（`let photo: Photo`）。最下部にボタンを置くなら `ScrollView` 内 `VStack` 末尾、または `.safeAreaInset(edge: .bottom)`（既に TTS バーで使用中）。削除後は `dismiss()` でレッスン画面へ戻す。
- **モデル/削除の注意点**:
  - `Lesson.photos` は `@Relationship(deleteRule: .cascade, inverse: \Photo.lesson)`。これは Lesson 削除時の挙動。個別 Photo は `modelContext.delete(photo)` で明示削除する。
  - `WordOccurrence.sourcePhoto: Photo?` は **inverse 未宣言**。Photo を消すとダングリング参照になりうるため、削除前に該当 occurrence の `sourcePhoto` を `nil` にする（occurrence 自体は残す＝単語のレッスン紐付けは維持）。
  - 画像ファイルは `PhotoStorage.delete(fileName: photo.imageFileName)` で削除（既存 API）。
  - autosave 任せにせず `modelContext.saveOrLog()` で明示保存（既存 `removeWordFromLesson` と同方針）。

## 対応方針

共通の削除処理を `LessonsView` に private メソッドとして実装し、両起点から呼ぶ。詳細画面は `let photo` のみ保持で `modelContext` を持つため、詳細側は自前で削除して `dismiss()` する（同じ削除ロジックを小さなヘルパに切り出す）。

### 削除ロジック（共通）

```
1. WordOccurrence.sourcePhoto == photo のものを nil 化（occurrence は残す）
2. PhotoStorage.delete(fileName: photo.imageFileName)
3. modelContext.delete(photo)
4. modelContext.saveOrLog()
```

- SwiftData の `sourcePhoto` を安全に扱うため、`photo.lesson.wordOccurrences` を走査して `occurrence.sourcePhoto?.id == photo.id` を nil 化する。

### Step 1: 一覧の左スワイプ削除（LessonsView）

- Content セクションの `ForEach(photos)` の各行に `.swipeActions(edge: .trailing)` を追加し、`Button(role: .destructive)`「Delete」（`trash` アイコン）で `deletePhoto(photo)` を呼ぶ。
- 単語行の Remove と UI を揃える。

### Step 2: 詳細画面の最下部 delete ボタン（PhotoDetailView）

- `ScrollView` 内 `VStack` の末尾（既存コンテンツの下）に、区切りを置いて破壊的スタイルの「Delete Photo」ボタンを配置。
- タップで削除ロジックを実行し `dismiss()`。`@Environment(\.dismiss)` と `@Environment(\.modelContext)` を追加。
- 削除ロジックは `LessonsView` と重複するため、`Photo` 削除の共通処理を `PhotoStorage` 隣接のヘルパ、または `Photo` の拡張/`modelContext` 拡張として切り出して両画面から使う（実装時に最小の重複で判断）。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/LessonsView.swift`（Content 行に swipeActions、`deletePhoto` 追加）
- `ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`（最下部 delete ボタン、dismiss、modelContext 追加）
- 共通削除ヘルパの置き場所（新規 or 既存 Support への追記）
- モデル・バックエンド変更なし。SwiftData マイグレーション不要。

## テスト方針

- **ビルド**: `xcodegen generate`（新規ファイルを足す場合）後にビルド成功。既存ファイル改変のみなら generate 不要。
- **手動（`/run`）**:
  - 一覧で写真行を左スワイプ → Delete → 行が消え、Content 件数が減る。
  - 詳細画面の最下部 Delete → 削除されレッスン画面に戻る。
  - 削除した写真の画像ファイルが消えていること（再表示で無いこと）。
  - その写真由来で登録した単語がレッスンの Words に残っていること（occurrence は消さない）。
  - pending/processing 中の写真も削除できること。
