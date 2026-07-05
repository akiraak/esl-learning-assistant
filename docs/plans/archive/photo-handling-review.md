# 写真の扱いを検討する（調査・設計プラン）

## 目的・背景

現状、写真（`Photo` エンティティ）は「教科書ページを撮影し OCR・翻訳する」用途に特化しており、
必ずレッスンに従属する設計になっている。しかし実際の学習では、教科書コンテンツ以外にも
写真を残したい場面（板書・先生の手書きメモ・宿題プリント・レッスンにまだ紐付けていない撮り置き 等）
が想定される。

本タスクでは実装に着手する前に、写真の位置づけを以下の3つの観点で整理し、
今後どのデータモデル／UI に向かうかの**設計方針を確定する**ことを目的とする。
（本タスクはドキュメント作成・設計判断が成果物。コード実装は別タスクに切り出す。）

1. レッスンのコンテンツとして
2. レッスンのメモとして
3. レッスンに紐付かない写真の可能性

## 現状整理（調査結果）

### データモデル

- `Photo`（`ios/.../Models/Photo.swift`）
  - `var lesson: Lesson`（**非オプショナル＝レッスン必須**）
  - `imageFileName` / `capturedAt` / `processingStatus` / `processingErrorMessage?`
    / `ocrText?` / `translatedText?` / `translationLanguage?`
  - 画像本体は `Documents/Photos/` にファイル保存し、モデルはファイル名のみ保持
- `Lesson`（`ios/.../Models/Lesson.swift`）
  - `@Relationship(deleteRule: .cascade) var photos: [Photo]`
  - `var memo: String?`（**テキストのみ。写真添付は不可**）
- スキーマ全体は [docs/specs/data-model.md](../specs/data-model.md) を参照

### 写真の現在のライフサイクル

- `LessonsView` の「**Content**」セクション（＝`lesson.photos`。テキスト等の他コンテンツ型は無く
  **写真だけがレッスンのコンテンツ**）の「+」ボタンからのみ `CaptureView(lesson:)` を起動
- `CaptureView` で撮影 → 即 `OCRTranslationService.process` を呼び OCR・翻訳
- 未処理（`.pending`/`.failed`）分は `PhotoDetailView`・レッスン一括翻訳で後追い処理
  （[archive/translate-pending-photos.md](archive/translate-pending-photos.md)）
- OCR 結果は Markdown 化して表示・タップで単語登録
  （[archive/markdown-ocr-translation.md](archive/markdown-ocr-translation.md) /
  [archive/ocr-tap-word-add.md](archive/ocr-tap-word-add.md)）

### 現状の制約

- 写真＝「OCR・翻訳される教科書コンテンツ」と一体化しており、用途を選べない
- レッスンに紐付かない写真は表現できない（`Photo.lesson` が必須）
- メモに写真を添付できない（`memo` は `String?`）

## 検討観点

### 観点1: レッスンのコンテンツとして

現状の `Photo` の役割。教科書ページを撮影し OCR・翻訳して学習素材にする。

- 論点: この用途は現状のままで十分か。OCR 対象／非対象を写真ごとに選べる必要はあるか
  （例: OCR したくない図版・写真も「コンテンツ」として残したい場合）
- 論点: 「コンテンツ写真」と後述のメモ写真を**同じ `Photo` に種別フラグで持たせる**か、
  **別エンティティに分ける**か

### 観点2: レッスンのメモとして

授業中の補足を残す `Lesson.memo`（現状テキストのみ）に写真も添付できるようにするか。

- ユースケース: 板書・先生の手書きコメント・宿題プリントの撮影 等（OCR 不要な想定が多い）
- 論点: メモ写真は OCR・翻訳の対象にしない（or 任意）でよいか
- 論点: モデル表現の選択肢
  - (a) `Photo` に `role`（`content` / `memo`）を追加し、レッスン配下で用途を区別
  - (b) メモ専用の軽量エンティティ（OCR フィールドを持たない）を新設
  - (c) `Lesson.memo` を廃し、テキスト＋写真を持つ `LessonNote` 系に再設計

### 観点3: レッスンに紐付かない写真の可能性

レッスン確定前の撮り置きや、どのレッスンにも属さない参考写真を許容するか。

- ユースケース: 先に撮ってから後でレッスンを選ぶ／複数レッスンにまたがる資料
- 論点: `Photo.lesson` を**オプショナル化**して未所属を許すか、
  「未整理（inbox）」の受け皿を用意して後からレッスンへ移動させるか
- ⚠️ **マイグレーション注意**: `Photo.lesson` の必須→オプショナル化や新規リレーション追加は
  SwiftData のストア互換に影響しうる。追加フィールドは必ず nullable ストレージ＋computed 既定値で。
  （既知の地雷: 非オプショナル追加でストアが開けなくなる／CodingKeys リネームで黙って未永続化）
- ⚠️ **波及注意（マイグレーション以外）**: `WordOccurrence.sourcePhoto` と
  `WordAIInfoGenerator` は `sourcePhoto → lesson → ocrText` の経路で単語登録コンテキストを取得している。
  `Photo.lesson` をオプショナル化すると、この文脈解決やカスケード削除の前提が崩れるため、
  影響箇所（`WordRegistrar` / `WordAIInfoGenerator` / 削除ロジック）の見直しが必要

## 対応方針（調査の進め方）

- Step 1: 上記3観点のユースケースを洗い出し、必要／不要を判断する
- Step 2: データモデルの選択肢（`Photo` に種別追加 / 別エンティティ / `lesson` オプショナル化）を
  マイグレーション影響とあわせて比較し、方針を1つに決める
- Step 3: UI 影響（`CaptureView`・`PhotoDetailView`・`LessonsView`・`LessonMemoEditView`）を洗い出す
- Step 4: 決定内容を [docs/specs/data-model.md](../specs/data-model.md) に反映し、
  実装タスクを `TODO.md` に切り出す

## 影響範囲

- 調査・設計フェーズ: ドキュメントのみ（本プラン / `docs/specs/data-model.md` の更新）
- 実装は別タスク。想定影響先（実装時）:
  - `ios/.../Models/Photo.swift`（種別 or オプショナル化）／`Lesson.swift`（メモ写真関連）
  - `ios/.../Views/CaptureView.swift` / `PhotoDetailView.swift` / `LessonsView.swift`
    / `LessonMemoEditView.swift`
  - `docs/specs/data-model.md`（スキーマ確定内容の反映）
- バックエンド: OCR・翻訳の対象範囲が変わる場合のみ影響（原則、写真の種別判定は iOS 側）

## テスト方針

- 本タスク（調査・設計）はドキュメント成果物のためテストコードなし
- 設計判断がデータモデル変更を伴う場合、実装タスク側で SwiftData の
  ライトウェイトマイグレーション互換（既存ストアが開けること）を in-memory / 実機で検証する方針を明記する
