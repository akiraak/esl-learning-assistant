# レッスン詳細コンテンツの複数タイプ対応

## 目的・背景

レッスン詳細画面の「コンテンツ」を、単一種別（写真＋翻訳）ではなく複数種別を
まとめて扱えるようにする。扱うコンテンツタイプは次の3つ。

- **写真＋翻訳**（既存 `Photo`）
- **Audio**（既存 `AudioClip`）
- **YouTube リンク**（新規）

あわせて、コンテンツ追加の「＋」ボタンを押したときに、いきなり写真取り込みへ
進むのではなく、**タイプを選択する画面を1枚挟む**（写真 / Audio / YouTube を選ぶ）。

### 現状（調査結果）

- `LessonsView.swift` の `lessonContent(_:)` 内で、コンテンツは種別ごとに
  **別セクション**として並んでいる。
  - `Content` セクション（`LessonsView.swift:182-232`）… `lesson.photos` を一覧。
    ヘッダーの「＋」は直接 `CaptureView`（写真取り込み）を開く。
  - `Audio` セクション（`LessonsView.swift:297-328`）… `lesson.audioClips` を一覧。
    ヘッダーの「＋」は `.fileImporter` を開く。
  - このほか Words / Memo / Questions セクションがある（本タスクの対象外）。
- モデル
  - `Photo`（`Models/Photo.swift`）: `lesson: Lesson` の **to-one**（cascade）。
    OCR・翻訳・`WordOccurrence.sourcePhoto` 等の依存ロジックあり。
  - `AudioClip`（`Models/AudioClip.swift`）: `lessons: [Lesson]` の **多対多**（nullify）。
    実体は `AudioStorage`、Audio タブ（`AudioView`）でもライブラリとして共有。
  - YouTube は未実装。
- `ModelContainer` のスキーマ列挙は多数の箇所に重複。すべてに新規モデルを追加する必要がある。
  - 本体: `ESLLearningAssistantApp.swift:14`
  - デバッグ全消し: `SettingsView.swift:216`
  - プレビュー/inMemory: `ContentView.swift:54`, `LessonsView.swift:539`,
    `ReviewSessionView.swift:825`, `CompositionsView.swift:148`, `WordAddView.swift:102`,
    `ClassAddView.swift:53`, `ClassEditView.swift:51`, `WordsView.swift:188`,
    （`CompositionDetailView.swift:255` は個別 `try! ModelContainer(...)`）
  - **テストターゲット**（見落とし注意）: `WordAIInfoTests.swift`,
    `DebugDataCleanerTests.swift`, `WordRegistrarTests.swift`, `LessonMemoTests.swift`,
    `WordReviewStatePersistenceTests.swift`
- 一括削除: `Support/DebugDataCleaner.swift`。

## 対応方針

### モデル設計（重要な判断）

**既存3種別を1エンティティに統合しない。** `Photo`・`AudioClip` は成熟した
エンティティで、OCR・翻訳・`WordOccurrence.sourcePhoto`・多対多共有・ストレージ等の
依存が多い。1つの汎用エンティティへ畳み込むのは高リスクな SwiftData マイグレーションで、
機能上の利点もない。

要件の本質は **表示（コンテンツ欄に種別をまとめる）** と **追加 UX（タイプ選択画面）** で、
どちらも UI 層の関心事。したがって:

- **新規 `YouTubeLink` モデルのみ追加**する（軽量マイグレーションで済む）。
- 写真・Audio・YouTube の **統合はビュー層で行う**（共通タイムスタンプで
  1つの一覧にマージ・降順ソート）。
- Audio の独立セクションは廃止し、Content セクションに畳み込む。
  （Audio タブ `AudioView` は据え置き。レッスン詳細の見せ方だけ変える）

> メモ参照: `swiftdata-codable-migration-pitfall` / `ios-swiftdata-new-entity-checklist`。
> 新規 `@Model` 追加 + `Lesson` への to-many 追加（既定は空配列）は軽量マイグレーション可。

#### `YouTubeLink`（新規 `@Model`）

- `id: UUID`
- `lesson: Lesson` … **to-one / cascade**（`Photo` と同様。レッスン固有コンテンツ）
- `videoID: String` … 動画 ID（11桁）。入力から抽出・保存する主キー的な値
- `title: String?` … **ユーザー入力はしない**。表示は videoID を使う。
  将来キー不要の oEmbed（`youtube.com/oembed`）で自動取得する場合に備えて optional を残す（既定 nil）
- `addedAt: Date`
- `Lesson` 側に `@Relationship(deleteRule: .cascade, inverse: \YouTubeLink.lesson) var youtubeLinks: [YouTubeLink] = []` を追加。

> **方針: API キー不要。動画IDを指定して追加する。** YouTube 検索（Data API）は
> キー・クォータ管理が手間なので採用しない。ユーザーが**動画ID（または URL）を入力**し、
> クライアント側で 11桁の videoID を取り出して保存する。バックエンド変更なし。

入力パース（`YouTubeURL`、純関数・ユニットテスト対象）: 次のいずれからでも videoID を抽出。
- **動画IDそのもの**（`[A-Za-z0-9_-]{11}`）
- URL: `youtu.be/<id>` / `youtube.com/watch?v=<id>` / `/shorts/<id>` / `/embed/<id>`
- 抽出不可なら nil（追加不可）

### UI 設計

#### 統合コンテンツ一覧（表示）

ビュー層に種別を束ねる列挙を導入する。

```swift
enum LessonContentItem: Identifiable {
    case photo(Photo)
    case audio(AudioClip)
    case youtube(YouTubeLink)
    var sortDate: Date { /* capturedAt / importedAt / addedAt */ }
    var id: String { /* 種別プレフィックス + UUID */ }
}
```

- `photos + audioClips + youtubeLinks` を `sortDate` 降順でマージし、Content セクションで
  1つの `ForEach` として描画。
- 行は種別ごと: 既存 `PhotoRow` / `AudioClipRow` / 新規 `YouTubeRow`。
- タップ挙動を種別ごとに維持:
  - 写真 → `PhotoDetailView`（既存 `selectedPhoto`）
  - Audio → `AudioDetailView`（既存 `selectedAudioClip`）
  - YouTube → `YouTubeDetailView`（新規）
- スワイプ削除も種別ごとに維持（写真の削除確認ダイアログ、Audio・YouTube の削除）。
- ヘッダーのカウントは合算（写真＋Audio＋YouTube）に変更。
- 空状態「No content yet」は合算リストの空判定に変更。
- 「Translate Untranslated Photos」ボタンは写真のみ対象のまま残す。
- 既存の `Audio` セクションブロックは削除。

#### タイプ選択画面（追加フロー）

「＋」タップ時に **1枚の選択画面**（新規 `AddContentTypeView`）をシートで提示。
写真 / Audio / YouTube の3択を並べ、選択に応じて対応する追加 UI へ進む。

- 実装は `AddContentTypeView` 内に `NavigationStack` を持たせ、その中で完結させる方針。
  - 写真 → 既存 `CaptureView` フロー
  - Audio → 既存 `.fileImporter`
  - YouTube → 新規 `YouTubeAddView`
- 完了時はフロー全体（シート）を閉じてレッスン画面へ戻る。
- これにより現状の Content「＋」（直接 `CaptureView`）と Audio「＋」を置き換える。
  （`LessonsView` が抱える複数 `@State` シートを、この1コンポーネントへ集約できる）

#### YouTube の追加（動画ID / URL を指定）

`YouTubeAddView`（`Form` + Cancel/Add ツールバー。`AudioImportLessonView` に倣う）:
- 入力フィールドは **1つだけ**:「YouTube video ID or URL」。動画ID直接でも URL 貼り付けでも可。
- 入力から `videoID` を抽出 → **取れたらサムネイルをプレビュー表示 & Add を有効化**。
  取れなければ Add 無効（「Invalid YouTube video ID or URL」）。
- タイトル入力はなし。
- Add で `YouTubeLink`（videoID のみ）を作成し、フローを閉じてレッスンへ戻る。

```
┌─ Add YouTube ──── [Cancel] [Add] ─┐
│  Video ID or URL                  │
│  [ dQw4w9WgXcQ  または URL       ] │
│                                   │
│  ▶️ (サムネイルプレビュー)         │  ← videoID が取れたら表示
└───────────────────────────────────┘
```

バックエンド変更・API キーは不要。

#### YouTube の表示・再生

- `YouTubeRow`: サムネイル（`https://img.youtube.com/vi/<id>/mqdefault.jpg` を
  標準 `AsyncImage` で表示。新規依存を増やさない）＋ videoID（`title` があればそれを表示）。
- `YouTubeDetailView`: `WKWebView`（`UIViewRepresentable` ラッパー）で
  `youtube-nocookie.com/embed/<id>` を埋め込み再生（アプリ内で完結）。
  最小構成なら外部 `openURL` で YouTube/Safari を開くフォールバックでも可。

## 影響範囲

### 新規ファイル（iOS）
- `Models/YouTubeLink.swift`
- `Support/YouTubeURL.swift`（動画ID / URL → videoID 抽出パーサ）
- `Views/AddContentTypeView.swift`（タイプ選択＋追加フローの集約）
- `Views/YouTubeAddView.swift`（動画ID / URL 入力）
- `Views/YouTubeDetailView.swift`（+ `WKWebView` ラッパー）
- `YouTubeRow`（`LessonsView.swift` 内 or 独立ファイル）
- テスト: `YouTubeURLTests.swift`

> バックエンド変更なし・API キー不要（動画ID指定方式）。

### 変更ファイル（iOS）
- `Models/Lesson.swift` … `youtubeLinks` リレーション追加
- `Views/LessonsView.swift` … Content 統合、Audio セクション削除、追加フロー差し替え、カウント/空状態
- `ModelContainer` のスキーマ列挙**全箇所**（本体・プレビュー・**テストターゲット**）に
  `YouTubeLink.self` 追加。追加後は `swift`/`xcodebuild test` でスキーマ不一致が出ないか確認。
- `Support/DebugDataCleaner.swift` … YouTube は to-one/cascade（Lesson→Class 配下）で
  `deleteAllClasses` に内包されるため個別削除は不要。外部ファイル実体も無い（確認のみ）。
- XcodeGen: 新規ファイル追加後は `xcodegen generate` が必要
  （メモ `ios-xcodegen-project`。pbxproj は生成物）。

## テスト方針

- **ユニット**: `YouTubeURL` → `videoID` 抽出（動画ID直接 / youtu.be / watch?v / shorts /
  embed / 不正入力で nil）。
- **マイグレーション**: 既存ストアを持つ状態でアプリ起動 → エラー画面なく開くこと
  （新規エンティティ + to-many 既定空配列で軽量マイグレーション）。
- **手動 E2E**:
  - 「＋」→ タイプ選択画面が出る → 各タイプの追加が成功する。
  - YouTube: 動画ID または URL を入力（タイトル入力なし）→ サムネプレビュー → 追加できる。不正入力は Add 無効。
  - Content 一覧が写真/Audio/YouTube を時系列（降順）で1つにまとめて表示。
  - 各行タップで正しい詳細へ、スワイプ削除が種別ごとに動作。
  - 既存写真の表示・OCR/翻訳、Audio タブ側の挙動が退行しないこと。
  - `WordOccurrence.sourcePhoto` 系ロジックに影響が無いこと。

## Phase / Step

- **Phase 1: `YouTubeLink` モデル基盤**
  - `YouTubeLink.swift` 追加＋`Lesson.youtubeLinks` リレーション
  - `YouTubeURL` パーサ（動画ID / URL → videoID）＋ユニットテスト
  - `ModelContainer` 全登録箇所に追加、`xcodegen generate`、起動マイグレーション確認
- **Phase 2: YouTube の追加・表示・再生**
  - `YouTubeAddView`（動画ID / URL 入力のみ・タイトル入力なし・サムネプレビュー）/ `YouTubeRow` /
    `YouTubeDetailView`（WKWebView 埋め込み）
- **Phase 3: コンテンツ統合表示**
  - `LessonContentItem` 導入、写真＋Audio＋YouTube をマージ・降順表示
  - Audio 独立セクション廃止、カウント/空状態/スワイプ/タップ挙動を種別ごとに維持
- **Phase 4: タイプ選択の追加フロー**
  - `AddContentTypeView`（写真/Audio/YouTube の1画面）＋ルーティング
  - Content「＋」と Audio「＋」を新フローへ差し替え
- **Phase 5（任意）: 仕上げ**
  - サムネイル整備、空状態文言調整、（希望あれば）oEmbed でタイトル自動取得（キー不要・入力なし）
