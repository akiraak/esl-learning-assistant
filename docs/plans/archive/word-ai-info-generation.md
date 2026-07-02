# 単語情報のAI生成（サーバ生成・クライアント表示）

## 目的・背景

単語帳（Phase 2）の中核機能。現在の `Word` はユーザー入力の訳語のみが実質的な情報で、
`exampleSentence` / `partOfSpeech` / `grammarNote` は入力手段がなくほぼ空のまま。
単語登録時にバックエンド経由で Claude API を呼び出し、学習に必要な単語情報を自動生成して
詳細画面に表示する。

方針決定済み（2026-07-01 ユーザー確認）:

- 情報セットは**フルセット**（下記「単語に持たせる情報」）
- 生成タイミングは**登録時に自動**（失敗時は再試行、成功後も再生成可能、既存単語は一括生成）
- 語義には母語訳に加えて**英語での定義（英英辞書スタイル）**も含める

## 単語に持たせる情報（確定仕様）

AI生成物はユーザー入力と分離した埋め込み構造体 `WordAIInfo` にまとめて持つ。
ユーザーが登録した `translation`（一覧表示用の短い訳）はそのまま残し、上書きしない。
既存の `exampleSentence` / `partOfSpeech` / `grammarNote` も温存する（教科書抜粋・手動入力用）。

```
WordAIInfo (Codable, Wordに埋め込み)
├─ senses: [Sense]               // 語義 1〜3件。教科書文脈で使われた語義を先頭にする
│   ├─ meaning: String           //   母語での意味
│   ├─ englishDefinition: String //   英語での定義・言い換え（英英辞書スタイル。ESL学習者向けに平易な語彙で）
│   ├─ partOfSpeech: String      //   品詞（母語表記。例:「動詞」）
│   └─ note: String?             //   ニュアンス・使い分け
├─ pronunciation: Pronunciation
│   ├─ ipa: String               //   IPA発音記号（例: /ˈæp.əl/）
│   └─ syllables: String?        //   音節区切りとアクセント位置（例: AP-ple）
├─ inflections: [Inflection]     // 語形変化（該当するもののみ。0件可）
│   ├─ form: String              //   変化の種類（母語。例:「過去形」）
│   └─ text: String              //   変化形（例: "ran"）
├─ examples: [Example]           // 例文 2〜3件（教科書の文脈に合う場面設定）
│   ├─ english: String
│   └─ translation: String       //   母語訳
├─ collocations: [String]        // よく使う組み合わせ 0〜3件（例: "make a decision"）
├─ synonyms: [String]            // 類義語 0〜3件
├─ antonyms: [String]            // 反意語 0〜3件
├─ usageNote: String?            // 使用上の注意（可算/不可算、自他、前置詞の組み合わせ等）
├─ cefrLevel: String?            // 難易度目安 "A1"〜"C2"
├─ etymology: String?            // 語源・記憶のヒント（覚え方）
├─ register: String?             // 使用域（フォーマル/カジュアル/スラング等）
└─ commonMistakes: String?       // よくある間違い（母語話者が混同しやすい点）
```

`Word` へのフィールド追加（すべて optional / デフォルトありで軽量マイグレーション）:

| フィールド | 型 | 説明 |
|---|---|---|
| aiInfo | WordAIInfo? | 生成結果（未生成は nil） |
| aiInfoStatus | WordAIInfoStatus | `none` / `generating` / `completed` / `failed`（初期値 none） |
| aiInfoGeneratedAt | Date? | 生成日時 |
| aiInfoModel | String? | 生成に使ったモデル名 |
| aiInfoLanguage | String? | 生成時の母語（母語設定変更後の再生成判断に使う） |

- AI生成物を `aiInfo` 1フィールドに分離しておくことで、TODO の
  「単語のAI生成物を全て削除」（デバッグメニュー）は `aiInfo = nil` +
  `aiInfoStatus = .none` に戻すだけで実現できる（本プランのスコープ外）

## 対応方針

### Phase 1: バックエンド `/api/word-info`

- `POST /api/word-info`
  - リクエスト: `{ word, targetLanguage, context?, userTranslation? }`
    - `context`: 単語が登場した教科書本文（OCR結果の周辺テキスト）。語義の文脈判定に使う。
      手動登録などで文脈が無い場合は省略可
    - `userTranslation`: ユーザーが入力した訳語（語義判定のヒント）
  - レスポンス: `{ wordInfo: {...WordAIInfoと同構造...}, model }`
- `ocrTranslate.ts` の `callStructured` を流用し、`WordAIInfo` と同構造の JSON Schema で
  structured output 生成する（`wordInfo.ts` を新設）
- モデルは `config.wordInfoModel`（環境変数 `ANTHROPIC_WORD_INFO_MODEL`、
  既定 `claude-haiku-4-5`）。1単語あたり出力 1000 トークン前後の想定で低コスト
- ログ: SQLite に `word_info_requests` テーブルを新設
  （word / target_language / context有無 / model / tokens / cost / status / error / latency）し、
  管理画面に一覧・詳細表示を追加する（既存 `requests` テーブルはOCR専用構造のため分ける）
- `pricing.ts` に使用モデルの単価が無ければ追加する

### Phase 2: iOSデータモデル拡張＋生成サービス＋登録時自動生成

- `Word.swift` に `WordAIInfo` / `WordAIInfoStatus` と上記フィールドを追加する
- `RemoteWordInfoService` を新設（`RemoteOCRTranslationService` と同様の作り。
  `backendBaseURL` 設定を参照して `/api/word-info` を呼ぶ）
- 生成ヘルパー `WordAIInfoGenerator`（`@MainActor`）を新設
  - `generate(for word: Word)`: status を `generating` にして API 呼び出し →
    成功で `aiInfo` 格納・`completed`、失敗で `failed`
  - context は `word.occurrences` の `sourcePhoto?.ocrText` から取得する
    （現状は手動登録のみで nil。OCRタップ登録（別TODO）実装後に自然に効き始める）
- `WordAddView` の登録成功時に生成を開始する（画面は閉じてバックグラウンドで継続）

### Phase 3: 詳細画面表示＋再試行・再生成

- `WordDetailView` に AI生成情報のセクションを追加する
  - 発音（IPA・音節）／語義リスト（母語訳＋英語定義）／語形変化／例文（英語＋訳）／コロケーション／
    類義語・反意語／使用上の注意／CEFR・使用域（バッジ的表示）／語源・記憶のヒント／
    よくある間違い
  - 空の項目（nil・空配列）はセクションごと非表示にする
  - `generating`: ProgressView＋「生成中」表示
  - `failed`: エラー表示＋「再試行」ボタン
  - `completed`: ツールバーメニューに「AI情報を再生成」を追加（確認つき）
- 既存の手動フィールド（例文・品詞・文法）はAI情報と別セクションのまま温存する

### Phase 4: 既存単語の一括生成＋一覧のステータス表示

- `WordsView` のツールバーに「未生成の単語をまとめて生成」を追加
  （`aiInfoStatus == .none / .failed` の単語を順次生成。逐次実行で件数表示）
- 一覧の行に生成状態の小アイコンを表示（generating: スピナー、failed: 警告アイコン。
  completed は表示なし＝ノイズにしない）

## 影響範囲

- backend: `src/index.ts`（エンドポイント追加）、新規 `src/wordInfo.ts`、
  `src/db.ts`（`word_info_requests` テーブル）、`src/admin.ts`（ログ表示）、
  `src/config.ts`（`wordInfoModel`）、`src/pricing.ts`（必要なら単価追加）
- iOS: `Sources/Models/Word.swift`（`WordAIInfo` ほか追加）、
  新規 `Sources/Services/RemoteWordInfoService.swift`、
  新規 `Sources/Support/WordAIInfoGenerator.swift`、
  `Sources/Views/WordAddView.swift`（登録時トリガー）、
  `Sources/Views/WordDetailView.swift`（表示・再試行・再生成）、
  `Sources/Views/WordsView.swift`（一括生成・ステータス表示）

## テスト方針

- backend: `curl` で実キー呼び出しを確認する
  （文脈あり／なし、多義語（例: "run", "book"）で語義の文脈判定が効くこと、
  管理画面にログ・コストが出ること）
- iOS ユニットテスト:
  - `WordAIInfo` のJSONデコード（バックエンドのレスポンス形との整合）
  - `WordAIInfoGenerator` のステータス遷移（モックサービスで 成功→completed／失敗→failed）
- UIテスト: ネットワーク非依存の範囲のみ（未生成単語の詳細画面に生成ステータスUIが
  出ること）。生成フルフローはローカルバックエンド起動状態のシミュレータで手動確認する
- 既存データのマイグレーション確認（追加フィールドはoptional/デフォルトありのため
  軽量マイグレーションで既存単語が壊れないこと）
