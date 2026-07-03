# 復習クイズ問題のサーバ生成・保存化

## 1. 目的・背景

- 現状（[word-memorization-quiz.md](word-memorization-quiz.md) Phase 3 実装済み）は、復習クイズの問題を **iOS 端末内でルールベース生成**している（`ReviewQuestionBuilder`）。素材が `WordAIInfo` の使い回しのため、例文・誤答のバリエーションが単語帳の語彙に縛られる。
- これを **サーバで AI 生成（`callStructured`、wordInfo.ts と同パターン）して保存**する方式に変更する。**1単語 × 1出題形式につき複数バリエーション（variant）を保存**し、出題時はその中からランダムに選択する。
- 元プラン §3.3 の「v2: AI 生成問題を `POST /api/quiz` で追加」の前倒しに相当する。

**確定した設計判断**（ユーザー確認済み）:

1. 問題は **サーバで AI 生成**する（現行ロジックの TS 移植や iOS 生成のアップロードではない）
2. 生成タイミングは **単語の AI 情報生成時にまとめて**（事前生成。セッション開始時は取得のみ）
3. 出題は **サーバ保存問題のみ**。無い単語（オフライン・生成前・生成失敗）は出題しない
   （＝端末内のルールベース生成はフォールバックとしても残さず、生成コードを削除する）

## 2. 対応方針

### 2.1 DB（backend/src/db.ts）

```sql
CREATE TABLE IF NOT EXISTS quiz_questions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  word TEXT NOT NULL,              -- normalizeWordKey 済み（words テーブルと同じ）
  target_language TEXT NOT NULL,
  format TEXT NOT NULL,            -- "tc1"〜"vt2"（iOS ReviewQuestionFormat.rawValue と一致）
  variant_index INTEGER NOT NULL,  -- 0..N-1
  question_json TEXT NOT NULL,     -- §2.3 の問題 JSON
  model TEXT NOT NULL,             -- AI 生成モデル or "rule"（イラスト系）
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  cost_usd REAL NOT NULL DEFAULT 0,
  UNIQUE(word, target_language, format, variant_index)
)
```

- 生成は単語単位でまとめて置き換え（再生成時は該当 `(word, target_language)` の全行 DELETE → INSERT）。
- トークン・コストは呼び出し単位の値を同一バッチの行に按分せず、バッチ先頭行に記録…ではなく
  **呼び出しごとの値をそのグループの各行に均等按分**して記録する（管理画面での合計が実コストに一致）。

### 2.2 生成（新規 backend/src/quizQuestions.ts）

- 素材: `words` テーブルの `word_info_json`（無ければ 404。単語情報が先）。
- **バリエーション数: 1形式につき 3**（`VARIANTS_PER_FORMAT` 定数）。
- **AI 生成対象は24形式**（TC1〜TC10・TT1〜TT3・VC1〜VC7・VTC1・VTT1・VT1・VT2）。
  `callStructured` は `max_tokens: 4096` のため、**形式グループごとに分割呼び出し**する
  （例: [TC1-TC5] / [TC6-TC10] / [TT1-TT3, VT1, VT2] / [VC1-VC7, VTC1, VTT1] の4グループ、
  1呼び出しの出力 ≒ 15〜21問 ≒ 2〜3k tokens）。1グループの失敗は他グループに影響させない
  （部分成功を保存し、失敗グループはログに残す）。
- 素材が無い形式はグループのプロンプト構築時に除外する（例: synonyms 空 → TC4 を依頼しない、
  活用形の日→英マッピング不可 → TC7/TT3/VC7 を除外）。品詞・活用形ラベルの日→英マッピングは
  iOS `GrammarLabelMapping` と同じ固定テーブルを TS 側にも持つ。
- **イラスト系4形式（TC11・IC1・IT1・VC8）は AI 不要のルール生成**（問題文は定型、誤答は
  `word_illustrations` テーブルからランダムな他単語）。対象単語のイラスト + 他単語のイラスト3件以上が
  ある場合のみ生成し、`model = "rule"`・コスト0で保存する。
- **バリデーション**（AI 出力は信用しない）: 4択は options 4件・正規化キーで重複なし・
  correctIndex 範囲内、typing は acceptedAnswers 非空、VT2 は matchRateThreshold 付与。
  不正な variant は捨てる（形式ごとに 0〜3 件になり得る。0件ならその形式は出題されないだけ）。
- 音声系（VC/VTC/VTT/VT）の audioText は再生テキストとして保存。TTS 音声の事前合成はしない
  （既存どおり iOS 側で生成済みローカル TTS → 内蔵 TTS フォールバック）。

### 2.3 問題 JSON（iOS `ReviewQuestion` と 1:1 対応）

```jsonc
{
  "format": "tc3",
  "instruction": "Choose the word that completes the sentence.",
  "displayText": "She _____ the marathon in under four hours.",  // 無い形式は null
  "audioText": null,                    // 音声出題形式のみ
  "promptIllustrationWord": null,       // IC1・IT1 のみ（単語テキスト）
  "answer": {
    "type": "choices",                  // "choices" | "illustrationChoices" | "typing"
    "options": ["ran", "walked", "cooked", "slept"],  // choices 系のみ
    "correctIndex": 0,                  // choices 系のみ
    "acceptedAnswers": null,            // typing のみ
    "matchRateThreshold": null          // VT2 のみ 0.8
  }
}
```

### 2.4 API（backend/src/index.ts）

- `POST /api/quiz-questions/generate` `{ word, targetLanguage, regenerate? }`
  → 保存済みがあり regenerate でなければ `{ cached: true, count }`。
  無ければ生成・保存して `{ cached: false, count }`。word-info と同じ入力検証・ログ方針。
- `POST /api/quiz-questions/query` `{ words: string[], targetLanguage }`
  → 複数単語分の保存済み問題をまとめて返す `{ questions: { [word]: QuizQuestionJson[] } }`。
  セッション開始時に due 単語（最大20語）を1リクエストで取得するためのバッチ形式。

### 2.5 iOS

- **`Services/RemoteQuizQuestionService.swift`（新規）**: query / generate の呼び出し。
  `ReviewQuestion` と `ReviewQuestionAnswer` を Codable 化してサーバ JSON をデコードする
  （answer は type 判別のカスタムデコード）。
- **生成トリガ（WordAIInfoGenerator）**: 単語情報の生成成功後、fire-and-forget で
  `/api/quiz-questions/generate` を叩く（regenerate 時は `regenerate: true`）。
  失敗しても単語情報の成功表示には影響させない（次回セッション開始時の自己修復に任せる）。
- **ReviewSessionView**:
  - セッション開始時に due 単語（上限20）の問題を `/query` で一括取得（ローディング表示を追加）。
  - 単語ごとに `Set(取得した formats)` を作り、既存 `FormatSelector.select` の比率調整で形式を
    選択 → **その形式の variants からランダムに1件**出題する。
  - 問題が無い単語はスキップし、サマリーに「N 語は問題準備中のためスキップ」を表示。
    全語スキップなら「問題を準備中です。しばらくしてからもう一度」の状態表示。
  - **自己修復**: 問題が無かった due 単語は、その場で fire-and-forget の `/generate` を投げておく
    （既存単語のマイグレーション・過去の生成失敗の回復。次回セッションから出題可能になる）。
  - イラスト4択で誤答単語のイラストが端末に無い場合は既存実装どおり単語テキスト表示で代替
    （必要なら将来 `/api/word-illustration` での取得に拡張。今回はスコープ外）。
- **削除・整理**:
  - `ReviewQuestionBuilder` の問題生成ロジックと `ReviewQuestionBuilderTests` の生成系テストを削除。
  - `ReviewQuestion`・`ReviewQuestionAnswer`・`ReviewTypingSpec`・`ReviewAnswerJudge` は
    新規 `Support/ReviewQuestion.swift` に分離して存続（判定テストも存続）。
  - `FormatSelector` は `select`（比率調整）と `ReviewQuestionFormat` を残し、
    `availableFormats` / `ReviewWordMaterial` / `ReviewDistractorPool` と関連テストを削除。
  - `GrammarLabelMapping` は iOS では不要になる（生成がサーバに移るため）→ 削除し、TS 側へ移植。

### 2.6 管理画面（backend/src/admin.ts）

- `/admin/quiz-questions`: 単語×言語ごとの問題数・形式数・合計コストの一覧と、
  行展開（またはリンク）での variant 内容表示。単語単位の削除・再生成ボタン
  （words / illustrations ページのパターン踏襲）。

## 3. 影響範囲

- backend: `db.ts`（テーブル追加）、新規 `quizQuestions.ts`、`index.ts`（エンドポイント2本）、
  `admin.ts`（一覧ページ）、`ocrTranslate.ts`（callStructured に maxTokens 引数を追加する場合のみ）
- iOS: `ReviewSessionView.swift`（取得・選択ロジック変更）、`WordAIInfoGenerator.swift`（トリガ追加）、
  新規 `RemoteQuizQuestionService.swift`・`ReviewQuestion.swift`、
  削除 `ReviewQuestionBuilder.swift`・`GrammarLabelMapping.swift`（縮退）、`FormatSelector.swift`（縮退）
- docs: `word-memorization-quiz.md` に本プランへの参照を追記（§3.3 の v1 ローカル生成は本プランで置換）、
  `data-model.md` §7–8 の Question 注記更新、`app-spec.md` §3.3

## 4. コスト概算

- claude-haiku-4-5、1単語 = 4呼び出し・計 約70問: 入力 ~6k / 出力 ~10k tokens ≒ **$0.05前後/単語**
  （単語情報生成の数倍。管理画面のコスト記録で実測し、高ければ VARIANTS_PER_FORMAT を 2 に下げる）

## 5. テスト方針

- backend にテスト基盤が無いため、生成・検証ロジックは **サーバ起動 + curl での実機確認**
  （generate → query → JSON 構造・variant 数・バリデーション落ちの確認。admin ページ目視）。
- iOS: `ReviewQuestion` の Codable デコード（choices / typing / 判別失敗）をユニットテスト。
  `ReviewAnswerJudge`・`FormatSelector.select` の既存テストは存続。
- 通し確認: シミュレータでバックエンド（ローカル）に接続し、単語登録 → AI 情報生成 →
  問題生成 → 復習セッションがサーバ問題で完走することを UI テスト（`ReviewSessionUITests` を
  サーバ前提に更新）または手動で確認。オフライン時（サーバ未起動）に出題されないことも確認。

## 6. Phase 分割

- Phase A: backend — `quiz_questions` テーブル + `quizQuestions.ts`（AI 生成・検証・イラスト系ルール生成）
  + `/api/quiz-questions/generate`・`/query` + curl での動作確認
- Phase B: iOS — `RemoteQuizQuestionService` + `ReviewQuestion` Codable 分離 +
  ReviewSessionView のサーバ取得化 + WordAIInfoGenerator トリガ + ローカル生成コード削除・テスト整理
- Phase C: 管理画面 `/admin/quiz-questions` + docs 更新 + 通し確認・アーカイブ
