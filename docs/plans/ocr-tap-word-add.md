# 英文の単語タップで単語一覧に追加

## 目的・背景

写真OCRの英文（`PhotoDetailView` の「OCR Result (English)」）を読んでいる最中に、知らない単語をその場でタップして単語一覧（Word）に追加できるようにする。現状は `WordAddView` で単語を手入力するしかなく、教科書を読みながらの登録に手間がかかる。

タップ追加なら出現元の写真（`sourcePhoto`）とレッスンが自動で紐付き、AI生成に教科書文脈（OCR本文）もそのまま渡せる（後述）。

## 現状整理（調査結果）

- **英文を読む画面は `PhotoDetailView` のみ**。`Markdown(photo.ocrText ?? "")`（`Views/PhotoDetailView.swift:57`）で表示。英文実体は `Photo.ocrText: String?`（Markdown文字列）。表示は `processingStatus == .completed` 時。
- **単語追加ロジックは `WordAddView.addWord()`（`Views/WordAddView.swift:80-116`）に集約**:
  1. `allWords` から `text` を大文字小文字無視で重複チェック → 既存があれば再利用、無ければ `Word(text:, translation: "")` を insert。
  2. `WordOccurrence(word:lesson:)` を生成・insert し、`lesson.wordOccurrences.append(...)` も明示追加。
  3. `modelContext.saveOrLog()`。
  4. `aiInfoStatus` が `.none`/`.failed` なら `WordAIInfoGenerator.shared.generateInBackground(for: word)`。
- **`WordOccurrence` は `sourcePhoto: Photo?` を持つ**（`Models/WordOccurrence.swift:9`）。`WordAIInfoGenerator`（`Support/WordAIInfoGenerator.swift:31-34`）は `word.occurrences...sourcePhoto?.ocrText` を文脈として利用するため、**タップ追加で `sourcePhoto: photo` を渡せばAI生成にOCR文脈が自動で渡る**。
- **`Photo` は `lesson: Lesson` を持つ**ので、タップ追加時のレッスン紐付けは `photo.lesson` から得られる。
- **MarkdownUI 2.4.1 は個別単語のタップコールバックを標準提供しない**。既存に `openURL`/`onTapGesture` の Markdown 連携は無い。
- `PhotoDetailView` は現状 `@Environment(\.modelContext)` を持たないため、注入の追加が必要。

## 対応方針

### 採用案: OCRセクションに「単語追加モード」トグルを追加（推奨）

`PhotoDetailView` のOCRセクション見出しにトグルボタンを置き、ON時にMarkdown表示を**タップ可能な単語トークンのフローレイアウト**へ切り替える。

- 通常時は現状どおり `Markdown` で読みやすさを維持（見出しハイライト等を保持）。
- 単語追加モード時は `photo.ocrText` をプレーン化（既存 `plainText(_:)` `PhotoDetailView.swift:165` と同方式でMarkdown記号除去）して単語分割し、各単語を `Button`/`Text` として折り返しレイアウト表示。
- 各トークンの見た目で状態を区別:
  - 既に登録済みの単語（`@Query` の Word と大文字小文字無視で一致）→ 淡色 or チェック表示。
  - タップして今追加した単語 → 追加済みスタイルへ即時変化（フィードバック）。
- トークンをタップ → 共通の単語登録ヘルパー（後述 `WordRegistrar`）を `lesson: photo.lesson`, `sourcePhoto: photo` で呼び出し。

**この案を推奨する理由**: 読書体験（Markdown表示）を壊さず、登録済み状態の可視化やタップフィードバックを精密に制御できる。トークン化も独自制御できるため句読点・記号の扱いが安定する。

### 代替案: Markdownリンク方式（不採用寄り）

`ocrText` の各単語を `[word](eslword://word)` に前処理し、`Markdown` のまま `.environment(\.openURL, OpenURLAction{...})` で捕捉する。Markdown表現を流用できるが、全単語がリンク装飾（下線・色）になり読書時に煩雑。かつ見出し記号・既存リンク・句読点周りのトークン化がMarkdown構文と競合して壊れやすい。→ 不採用（採用案が難航した場合の保険）。

## 影響範囲

- **新規**: `Support/WordRegistrar.swift`（登録ロジックの共通化）、`Views/TappableOCRTextView.swift`（単語フロー表示。折り返しは iOS16+ `Layout` 準拠の簡易 FlowLayout か既存慣習に合わせる）。
- **変更**: `Views/PhotoDetailView.swift`（`@Environment(\.modelContext)` 注入、OCRセクションにモードトグルとタップビュー分岐を追加）。
- **変更**: `Views/WordAddView.swift`（`addWord()` を `WordRegistrar` 利用へ置換。挙動は不変）。
- SwiftData モデル変更なし（マイグレーション不要）。既存の `[Class, Lesson, Photo, Word, WordOccurrence]` 構成のまま。

## テスト方針

- **単体**: 単語トークナイザ（Markdown記号除去・句読点トリム・空白分割・非英字トークン除外・重複判定用の正規化）を新規テスト。
- **単体**: `WordRegistrar` の登録ロジック（重複時の再利用／新規時の Word・WordOccurrence 生成・sourcePhoto 紐付け・AI生成トリガ判定）を検証。既存 `WordAIInfoTests`・`LessonWordAddUITests` の観点を流用。
- **UI**: `PhotoDetailView` で単語追加モードをONにし、トークンをタップ → 単語一覧に追加され、登録済み表示に変わることを確認（`LessonWordAddUITests` を参考に新規UIテスト）。
- 既存 `WordAddView` 経由の追加フローが `WordRegistrar` 化後もリグレッションしないことを既存テストで確認。

## 検証メモ（Phase 0: WordDetailView での実現性検証）

本命の OCR 英文（`PhotoDetailView` の MarkdownUI）に着手する前に、**プレーンな `Text` である `WordDetailView` の英文でタップ登録の実現性を先行検証**する。

- 対象: 「Example Sentence」（`word.exampleSentence`）と「Examples」（`example.english`）の英文。
- 実装: `WordDetailView.swift` 一枚に閉じた変更（新規ファイルなし＝pbxproj 変更不要）。
  - `TappableEnglishText`（private）: 英文を単語/区切りにトークン化し、各単語へ独自スキーム `eslword://add?w=<word>` のリンクを張る。`.environment(\.openURL, OpenURLAction)` でタップを横取りし、外部遷移させず登録ハンドラを呼ぶ。リンク色は `.primary` に上書きして本文と同じ見た目。
  - `registerTappedWord(_:)`: `WordAddView.addWord()` のレッスン紐付けなし版（同綴り再利用→新規作成→`saveOrLog`→AI 情報生成トリガ）。結果を一時トーストで表示。
- 検証観点: (1) 単語ごとのタップ検出が効くか、(2) 登録・重複判定・AI 生成トリガが期待どおり動くか、(3) `openURL` 横取りの見た目と操作感。
- 検証OK後、この `TappableEnglishText`＋トークナイザを別ファイルへ抽出（Phase 1/2）し、`PhotoDetailView` の OCR 英文へ展開する。

## Phase 構成

- **Phase 1**: 登録ロジックを `WordRegistrar` へ抽出し、`WordAddView` をそれ利用へリファクタ（挙動不変・既存テスト緑を維持）。
- **Phase 2**: 単語トークナイザ + `TappableOCRTextView`（フローレイアウト・タップ登録・登録済み/追加済み表示）を実装し、`PhotoDetailView` にモードトグルと `modelContext` 注入を追加。`sourcePhoto: photo` / `lesson: photo.lesson` で登録。
- **Phase 3**: 仕上げ（タップフィードバックのアニメーション、既に登録済み単語のハイライト、トークン化のエッジケース対応）とテスト整備。
