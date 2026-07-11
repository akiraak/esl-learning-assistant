# 熟語（2単語以上）を単語として扱う

TODO「熟語（２単語以上）を単語に入れる仕様を詰める」のプラン。
句動詞（look up, give in）・イディオム（take care of, by heart）などの複数語フレーズを、
単語帳（Word）の第一級市民として登録・学習できるようにする仕様を確定し、実装する。

## 確定事項（2026-07-10 ユーザー決定）

1. **主導線は手動入力**: 普段の流れは「授業等で熟語を知る → Add Word フォームに入力」。
   Phase 1（手動入力の熟語対応）が日常利用の本体。
2. **本文タップは案 A（文脈から熟語自動判定）**: 熟語の一部の単語をタップしたら、
   前後の文脈から熟語を自動認識して「“look up” で登録」を提案する（Phase 4）。
3. **クイズは vc2（綴り4択）のみ除外**: tc7（活用形4択）は句動詞なら成立するため
   素材ゲートに任せて残す。

## 目的・背景

ESL 学習では句動詞・イディオム・コロケーションが単語と同等に重要な語彙単位だが、
現状のアプリは事実上「1トークンの英単語」前提で作られている。

- 手動入力では "look up" のようなスペース入り文字列も**登録できてしまう**が、
  正規化は素通し・AI 情報やクイズは単語前提のまま、という半端な状態。
- 本文タップ登録は 1 語単位のリンクしか張らないため、熟語を本文から登録する導線が無い。

## 現状整理（調査結果 2026-07-10）

### 熟語をそのまま受け入れられる部分（変更不要 or 小修正）

| 層 | 現状 | 備考 |
|---|---|---|
| データモデル | `Word.text: String`（`Models/Word.swift:7`）はスペース入り文字列を格納可能。専用の正規化キー列は無く、照合は都度 caseInsensitive 比較 | **SwiftData モデル変更なし**で成立（マイグレーション地雷を踏まない） |
| backend キャッシュキー | `normalizeWordKey = trim + lowercase`（`backend/src/db.ts:859-861`）。内部スペースは保持 | word-info / normalize / quiz / illustration 全キャッシュがフレーズキーで成立 |
| TTS | `SpeechService.speak` / `TTSButton` / `TTSAudioStore`（sha256(model\|text)）はいずれも任意テキスト対応 | 変更不要 |
| クイズ回答判定 | `ReviewAnswerJudge.normalize`（`Support/ReviewQuestion.swift:114-121`）は空白分割→単一スペース連結で**複数語対応済み** | typing 形式はフレーズでも採点可能 |
| 品詞ラベル | `quizQuestions.ts:60-62` に `句動詞→phrasal verb / 熟語・イディオム→idiom` のマッピングが既に存在 | |
| 正規化 status | `WordNormalizeStatus.phrase`（`Models/WordNormalization.swift:48-49`、backend `wordNormalize.ts:37,47`）が既に存在 | ただし「訂正せず素通し」の扱い |
| ドキュメント | `docs/specs/data-model.md:323` は `text` を「見出し語・フレーズ」と既に記述 | |

### 単語前提のままの部分（本プランの改修対象）

| 層 | 問題 | 該当 |
|---|---|---|
| 正規化 | `phrase` は入力をそのまま返すだけで**原形化されない**。"looked up" が変化形のまま登録される | `backend/src/wordNormalize.ts:25-59` |
| 空白正規化 | trim のみで連続空白を畳まない。"look  up"（2スペース）と "look up" が別語・別キャッシュになる | `Support/WordRegistrar.swift:34`、`Views/WordAddView.swift:134-145` |
| 本文タップ | トークナイザが空白を区切り扱い（`Support/EnglishWordLink.swift:17-42`）で 1 語 = 1 リンク。**熟語をタップで登録する導線が無い** | `Views/TappableEnglishText.swift:42-74, 88-171` |
| AI 情報生成 | プロンプト/スキーマが単一語前提（IPA 発音・inflections 等） | `backend/src/wordInfo.ts:31-59` |
| クイズ生成 | 単語前提の形式がある: `vc2`（綴り4択・ミススペル選択肢）、`tc7`（活用形4択）等 | `backend/src/quizQuestions.ts:112-271` |
| 入力フォーム | placeholder "Word (e.g. apple)" が単語のみを示唆 | `Views/WordAddView.swift:31` |

## 対応方針（仕様案）

### 基本方針: 熟語も既存 `Word` で扱う（新エンティティ・新プロパティなし）

- `text` にスペースを含む形でそのまま格納する。SwiftData のモデル変更ゼロ
  （非オプショナル追加のマイグレーション地雷を回避。identity は従来どおり `Word.id`）。
- 熟語かどうかの分岐が必要な箇所は `text` に空白を含むかで判定する
  （必要なら `Word.isPhrase` computed を追加。ストレージには持たない）。

### 1. 見出し表記のルール

- **辞書見出しの基本形**で格納する: `look up` / `take care of` / `by heart`。
- 目的語プレースホルダ（sth / sb）は**付けない**。分離可能句動詞（look *it* up）などの
  用法は AI 情報の usageNote / grammarNote 側で説明する。
- `one's` が不可欠な定型（make up one's mind）のみ `one's` を許容する。
- このルールは正規化プロンプト（lemma の定義）に明記する。

### 2. 登録前の正規化

**(a) 機械的な空白正規化（LLM 以前）**
- `WordRegistrar.register` / `correct` と `WordAddView` の重複判定に
  「trim + 連続空白→単一スペース」を追加する。タップ登録も同経路なので共通で効く。

**(b) フレーズの原形化（backend プロンプト拡張）**
- lemma ルール「常に辞書の原形」（[word-normalize-misspelled-inflected-to-base](archive/word-normalize-misspelled-inflected-to-base.md) で確立）を**フレーズにも適用**する:
  - `looked up` → status=`inflected`, lemma=`look up`（中心動詞を原形化）
  - `takes care of` → status=`inflected`, lemma=`take care of`
  - 綴り間違いを含むフレーズ → status=`misspelled`, lemma=正しい原形フレーズ
  - 既に原形のフレーズ → status=`phrase`, lemma=入力どおり（確認 UI なしで即登録・従来どおり）
- iOS 側は `suggestsCorrection`（inflected / misspelled のとき確認 UI）の既存ロジックが
  そのまま機能するため、**ドキュメントコメントの追従のみ**（`Models/WordNormalization.swift`）。
- 文まるごとの誤登録ガード: 明らかな文（主語+動詞+終端句読点など）は `unknown` とする旨を
  プロンプトに明記する（機械的な語数上限は設けない）。

### 3. AI 情報生成のフレーズ対応（backend `wordInfo.ts`）

- プロンプトに「入力は複数語のフレーズ（句動詞・イディオム・コロケーション）の場合がある」旨と
  以下の指示を追加:
  - `senses.partOfSpeech` は `句動詞` / `熟語` 等を使う（既存の品詞マッピングと整合）
  - `inflections` は句動詞なら中心動詞を活用させた形（looked up / looking up / looks up）、
    固定イディオム（by heart 等）は空でよい
  - `pronunciation`（IPA）はフレーズ全体の発音をベストエフォートで（不自然なら省略可）
  - 分離可能句動詞・語順の制約は usageNote / commonMistakes で説明
- examples / collocations / synonyms / antonyms / cefrLevel はフレーズでもそのまま有意味。スキーマ変更なし。

### 4. 復習クイズのフレーズ対応（backend `quizQuestions.ts`）

- `AI_FORMAT_SPECS` の各形式に `supportsPhrase`（既定 `true`）を追加し、
  見出し語に空白を含む場合は `false` の形式の生成をスキップする。
- 除外形式（確定・2026-07-10）: **`vc2`（綴り4択）のみ除外**。
  - ミススペル選択肢の生成がフレーズでは不自然になりやすいため。
  - `tc7`（活用形4択）は句動詞なら inflections が生成され成立するため、
    既存の素材ゲート（`isAvailable`）に任せて残す。
  - `vt1`（ディクテーション）・`vc4`（聞き取り）・`vtt1`（穴埋め入力）は
    複数語入力でも `ReviewAnswerJudge.normalize` が空白を正規化するため成立する。
- `correctMustBeWord` の検証（`quizQuestions.ts:102, 395, 420`）は `normalizeKey` の
  文字列一致なのでフレーズでも成立（確認のみ・変更なし）。
- イラスト問題（ic1 / it1）: 誤答は他の登録語 text を使うためフレーズ混在でも動作する。
  熟語のイラスト生成品質は実測で確認し、不自然なら熟語をイラスト対象外にする判断を Phase 3 で行う。
- iOS 側（`FormatSelector` / `ReviewSessionView`）はサーバが生成しない形式は出題されないため
  **変更不要**（確認のみ）。

### 5. 登録導線

**(a) 手動入力（`WordAddView`）— Phase 1 で対応**
- 現状でもスペース入り入力は可能。placeholder を熟語も可と分かる文言に変更
  （例: `"Word or phrase (e.g. apple, look up)"`）。
- 重複判定・登録前に空白正規化を適用（2-(a)）。

**(b) 本文タップ — Phase 4 で対応（案 A に確定・2026-07-10）**

**採用: 案 A「文脈から熟語自動判定」**。熟語の一部の単語をタップしたら、タップ語と
その文（前後の文脈）を word-normalize API へ渡し、タップ語が句動詞/熟語の一部なら
「“look up” で登録」を既存の確認ダイアログに提案する（「“up” のまま登録」の逃げ道も残す）。
既存のタップ→正規化→確認フローの自然な拡張で 1 タップで済む。

- 実装ポイント: タップ位置を含む文の抽出（`EnglishWordLink` にタップ語の周辺文脈を
  取り出すヘルパを追加）、`RemoteWordNormalizeService` / `POST /api/word-normalize` に
  文脈パラメータ（`context`）を追加、確認ダイアログの提案文言。
- キャッシュ設計: 現行 `word_normalizations` は `UNIQUE(input, target_language)`。
  文脈付き呼び出しはキャッシュをバイパスするか、`(input, context_hash)` キーの
  別テーブル/列にするかを Phase 4 着手時に決める（文脈なし呼び出しの既存キャッシュは温存）。

不採用案（記録）:
- 案 B **編集シート**: backend 変更不要だが 2 ステップ操作になる。
- 案 C **連続タップで範囲選択**: 1語=1リンクの現行描画と相性が悪く実装が最重量。
- 案 D **手動入力のみ**: タップ導線なし。

### 6. 表示・検索

- `WordsView` の一覧行は 1 行表示のため、長いフレーズの truncation を実機確認（対応は必要時のみ）。
- 検索・ソートは `text` ベースの既存実装で成立（変更なし）。

## 影響範囲

### backend（プロンプト中心・スキーマ変更なし）
- `backend/src/wordNormalize.ts` — フレーズ原形化・見出し表記ルール・文ガードのプロンプト拡張
- `backend/src/wordInfo.ts` — フレーズ対応のプロンプト拡張（品詞・inflections・IPA・usageNote）
- `backend/src/quizQuestions.ts` — `supportsPhrase` ガード追加（vc2 除外）
- （案 A 採用時）`backend/src/index.ts` / `wordNormalize.ts` — 文脈パラメータの追加とキャッシュ設計

### iOS（SwiftData モデル変更なし・マイグレーション不要）
- `Sources/Support/WordRegistrar.swift` — 空白正規化（trim + 連続空白畳み込み）
- `Sources/Views/WordAddView.swift` — placeholder 文言、重複判定の空白正規化
- `Sources/Models/WordNormalization.swift` — ドキュメントコメント追従
- （Phase 4）`Sources/Views/TappableEnglishText.swift` / `Sources/Support/EnglishWordLink.swift` /
  `Sources/Services/RemoteWordNormalizeService.swift` — 採用した UX 案の実装

## テスト方針

- **backend（curl / `regenerate:true`）**:
  - `looked up` → inflected, lemma=`look up` / `takes care of` → inflected, lemma=`take care of`
  - `look up` → phrase, lemma=`look up`（回帰: `ran`→`run`, `apple`→canonical）
  - word-info: `look up` で 品詞=句動詞・inflections=中心動詞活用・examples 生成を確認
  - quiz 生成: フレーズ語で `vc2` が生成されない・他形式が成立・`correctMustBeWord` 通過
- **iOS 単体**: `WordRegistrar` の空白正規化と重複判定（"look  up" → "look up" に集約）、
  `ReviewAnswerJudge` の複数語 typing 採点（既存挙動の回帰確認）
- **iOS UI / 実機**: WordAddView から `looked up` 登録 → 確認 UI で `look up` 提示 → 登録 →
  詳細表示（AI 情報・TTS 発音）→ 復習クイズ一巡でフレーズ問題の出題・採点を確認
- 既存単語（1語）のフローに回帰が無いこと（既存 UI テスト緑維持）

## Phase / Step

- [x] Phase 0: 仕様確定（2026-07-10。主導線=手動入力 / タップ登録=案 A 文脈自動判定 / クイズ除外=vc2 のみ）
- [x] Phase 1: 基盤 — 空白正規化（iOS）+ フレーズ原形化（backend wordNormalize）+ WordAddView 文言（2026-07-10）
  - iOS: `WordRegistrar.normalizeSpacing`（trim + 連続空白→単一スペース）を追加し、
    `register` / `correct` / `WordAddView`（重複判定・正規化入力）で共通適用。placeholder を
    "Word or phrase (e.g. apple, look up)" に変更。単体テスト追加（全107テスト緑）。
  - backend: `wordNormalize.ts` のプロンプト・スキーマ説明をフレーズ対応に拡張。
    実測時「look up」（既に基本形）が inflected に揺れたため、
    「inflected/misspelled は lemma が入力と異なる（訂正がある）場合のみ。既に基本形なら
    単語=canonical / フレーズ=phrase」のルールを明記して安定化（4/4 で phrase）。
  - 実測結果（regenerate:true）: `looked up`→inflected/`look up`、`takes care of`→inflected/
    `take care of`、`by heart`→phrase、`take caer of`→misspelled/`take care of`、
    `ran`→inflected/`run`、`apple`→canonical、`I looked it up yesterday.`→unknown（文ガード）。
- [ ] Phase 2: AI 情報生成のフレーズ対応（backend wordInfo プロンプト）
- [ ] Phase 3: クイズ生成のフレーズ対応（supportsPhrase ガード + イラスト品質の実測判断）
- [ ] Phase 4: 本文タップからの熟語登録（案 A: 文脈から熟語自動判定）

## 留意点

1. ハイフン語との同一性（`check in` と `check-in`）は別語のまま扱う（正規化 LLM の lemma に寄せる）。
   問題が出たら正規化プロンプトで統一方針を決める。
2. 文脈付き正規化のキャッシュ設計（`UNIQUE(input, target_language)` が文脈で崩れる）は
   Phase 4 着手時に決める（5-(b) 参照）。
