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

## Phase 構成（旧・初期案）

- **Phase 1**: 登録ロジックを `WordRegistrar` へ抽出し、`WordAddView` をそれ利用へリファクタ（挙動不変・既存テスト緑を維持）。
- **Phase 2**: 単語トークナイザ + `TappableOCRTextView`（フローレイアウト・タップ登録・登録済み/追加済み表示）を実装し、`PhotoDetailView` にモードトグルと `modelContext` 注入を追加。`sourcePhoto: photo` / `lesson: photo.lesson` で登録。
- **Phase 3**: 仕上げ（タップフィードバックのアニメーション、既に登録済み単語のハイライト、トークン化のエッジケース対応）とテスト整備。

---

## 本命フェーズ: アプリ全体の英語へ展開（2026-07-04 確定）

検証（Phase 0）が成功し、`WordDetailView` の英文タップ登録が実用に足ることを確認した。
これをアプリのあらゆる英語箇所へ展開する。

### 重要な技術的発見: MarkdownUI でも単語タップは可能

当初 PhotoDetailView の OCR は MarkdownUI 表示のためタップ不可と考え「トグルで
プレーン表示へ切替」案を採っていたが、MarkdownUI 2.4.1 のソース調査で以下を確認した:

- MarkdownUI はリンク `[text](url)` を独自ジェスチャではなく **標準の
  `AttributedString.link`（URL属性）** としてレンダリングするだけで、独自の `openURL` を
  持たない。よって `Markdown(...)` を `.environment(\.openURL, OpenURLAction{...})` で
  包めば、プレーン `Text` の検証実装と**まったく同じ仕組み**でタップを横取りできる。
- 段落は1つの `Text` に連結されるため、1段落に多数の単語リンクを入れても自然に折り返す。
- リンクの見た目はテーマで完全にカスタム可能。
  `.markdownTextStyle(\.link) { ForegroundColor(.primary); UnderlineStyle(nil) }`
  （＋必要なら `.tint(.primary)`）で下線・色を消し、本文と見分けがつかなくできる。
- インライン単位のタップコールバックAPIは無いので、「各単語をリンク化 → openURL横取り」が
  唯一かつ正攻法。

→ **OCR は書式（見出しハイライト・太字）を保ったまま、トグル無しで常時タップ可能にする。**
プレーン英文とマークダウン英文を、共通のトークナイザ・`eslword://` スキーム・登録ハンドラで
統一する。

### 対応範囲（ユーザー確定・全4項目）

1. **OCR結果（PhotoDetailView）** — 本命。書式維持のまま常時タップ可。
2. **単語詳細の残り英語欄（WordDetailView）** — 英英定義・コロケーション・語形変化・
   類義/反意語。
3. **用法ノート等の混在欄（WordDetailView）** — Usage Notes/Etymology/Common Mistakes。
   英単語のみリンク化されるため母語混在でも安全。
4. **復習クイズのフィードバック（ReviewSessionView）** — 解答後のまとめカードの例文・
   displayText。回答ボタン自体はタップ登録対象外（回答操作と競合するため）。

### 共通アーキテクチャ

- **新規 `Support/EnglishWordLink.swift`（純ロジック・テスト対象）**
  - `tokenize(_:)`: 英文を単語/区切りへ分割（検証実装から移設）。
  - `linkedMarkdown(_:)`: マークダウン文字列の**単語だけ**を `[word](eslword://add?w=…)`
    に包む。見出し `#`・強調 `*`・区切りは非単語として素通し。**コードブロック/インライン
    コード/既存リンク・URL は破壊しないようガード**する（状態機械で1パス処理）。
  - `word(from: URL)`: `eslword://` リンクから単語をデコード。
  - URL は `URLComponents` 経由で組み立て、`'`・`-` を含む語も安全にエンコード。
- **新規 `Support/WordRegistrar.swift`（登録ロジック共通化・テスト対象）**
  - `register(text:in:existingWords:lesson:sourcePhoto:generateAIInfo:)`: 同綴り再利用→
    新規作成→（lesson 指定時）`WordOccurrence` 生成（同一 word+photo は重複ガード）→
    `saveOrLog`→AI情報生成トリガ。`generateAIInfo` はデフォルト実装を注入可能にして
    テストではネットワークを呼ばない。
  - `WordAddView.addWord()` と タップ登録の両方がこれを使う（挙動不変・DRY）。
- **新規 `Views/TappableEnglishText.swift`（SwiftUI + MarkdownUI）**
  - `WordTapAction` + `EnvironmentValues.wordTapAction`: `OpenURLAction` に倣った環境値。
    タップハンドラを環境で配布し、深いビュー階層（`WordAIInfoSections` 等）への
    `onWordTap` バケツリレーを解消する。
  - `TappableEnglishText(text:)`: プレーン英文用。`Text(AttributedString)` + 各単語リンク +
    `openURL` 横取り → `wordTapAction`。
  - `TappableMarkdown(markdown:)`: OCR等のマークダウン英文用。`Markdown(linkedMarkdown(...))`
    + リンクスタイル本文同化 + 見出しハイライト + `openURL` 横取り。
  - `markdownHeadingHighlight()` を PhotoDetailView から移設（Translation 側も引き続き利用）。
  - `WordRegistrationModifier` + `View.wordTapRegistration(currentWord:sourcePhoto:lesson:)`:
    `@Query allWords` と登録状態（確認ダイアログ・`navigationDestination`・トースト）を
    集約し、`\.wordTapAction` を環境へ注入する。既存語タップ→詳細へ遷移（自分自身はスキップ）、
    未登録語タップ→確認ダイアログ→`WordRegistrar` 登録→トースト。

### 変更ファイル

- `Views/WordDetailView.swift`: 私有の `TappableEnglishText`・タップ状態・
  `handleTappedWord`/`registerTappedWord`・確認ダイアログ・navigationDestination・トーストを
  削除し、`.wordTapRegistration(currentWord: word)` へ集約。`WordAIInfoSections` の
  `onWordTap` 引数を撤去（環境から取得）。残りの英語欄（englishDefinition・collocation・
  inflection.text・synonyms/antonyms・usageNote/etymology/commonMistakes）を
  `TappableEnglishText` 化。
- `Views/PhotoDetailView.swift`: OCR を `TappableMarkdown(photo.ocrText)` へ。ルートに
  `.wordTapRegistration(sourcePhoto: photo, lesson: photo.lesson)`。`markdownHeadingHighlight`
  は共通ファイルへ移設。Translation は非タップのまま。
- `Views/WordAddView.swift`: `addWord()` を `WordRegistrar` 利用へ（挙動不変）。
- `Views/ReviewSessionView.swift`: フィードバックカードの `example.english` と `displayText`
  を `TappableEnglishText` 化。ルート（or フィードバック領域）に `.wordTapRegistration()`。
  回答ボタンは対象外。
- pbxproj: 新規3ファイルを追加。

### テスト方針（更新）

- **単体（新規 `EnglishWordLinkTests`）**: トークナイザ、`linkedMarkdown` の
  見出し/強調保持・コード/リンク/URL ガード・アポストロフィ/ハイフン語・URLエンコード/
  デコード往復。
- **単体（新規 `WordRegistrarTests`）**: 再利用/新規作成、occurrence 生成と重複ガード、
  AI生成トリガ（注入した no-op で検証）。`generateAIInfo` 注入でネットワーク非依存。
- **UI**: 既存 `LessonWordAddUITests`・`WordDetailButtonsUITests` の緑維持。OCR タップ登録の
  UIテストを追加（PhotoDetailView で単語タップ→確認→単語一覧に追加）。
