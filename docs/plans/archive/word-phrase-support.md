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

## Phase 4 設計（2026-07-11 着手時決定）

### 文脈の取り方（iOS）: リンク URL にオフセットを載せ、タップ時に文を切り出す

- リンク URL に文そのものは埋めない（全単語分の AttributedString が肥大するため）。
  代わりに**タップ語の文字オフセット**を載せ、タップ時に 1 回だけ文を切り出す。
  - `TappableEnglishText`: `eslword://add?w=<word>&o=<offset>`（offset = `text` 内の文字位置）
  - `TappableMarkdown`: `eslword://add?w=<word>&b=<blockIndex>&o=<offsetInBlockText>`
    （openURL ハンドラはルート 1 箇所のままなのでブロック番号も必要。
    ブロックの素文 = spans の text 連結で、描画時のオフセットと厳密に一致する）
- `EnglishWordLink.sentenceContext(in:around:wordLength:)` を追加:
  タップ位置から前後へ文境界（`.` `!` `?` の直後が空白/末尾、または改行）を探して文を切り出す。
  最大 240 字（超える場合はタップ語中心のウィンドウ）。略語（e.g. 等）の誤分割はベストエフォート
  （文脈は LLM へのヒントであり多少切れても成立する）。
- `WordTapAction` を `(word, context?)` に拡張し、両ビューがタップ時に文脈を添えて呼ぶ。
  `WordRegistrationModifier.handleTap` → `WordNormalizationFlow.decide(context:)` →
  `WordNormalizeService.normalize(context:)` と素通しする。手動入力（WordAddView）は context=nil。

### status 追加: `phrase_part`

- backend / iOS 両方の enum に `phrase_part` を追加:
  「タップ語が文脈の文中で複数語表現（句動詞・イディオム）の一部として使われている」。
  lemma は**表現全体の辞書基本形**（分離目的語は除去: "looked it **up**" → `look up`）、
  reason は母語で必須（確認ダイアログの説明文になる）。
- iOS は `suggestsCorrection = true` にするだけで既存の確認ダイアログ
  （主=「Register “look up”」/ 逃げ道=「Keep “up”」/ Cancel）と dedup（lemma が既存語なら
  その詳細へ集約）がそのまま機能する。旧バージョン・未知 status は `.unknown` に倒れて安全。
- 文脈が無い呼び出し（手動入力）では phrase_part を使わない旨をプロンプトに明記。

### キャッシュ設計: 文脈付きは別テーブル（既存キャッシュを汚染しない）

- 文脈付き呼び出しが既存 `word_normalizations`（`UNIQUE(input, target_language)`）へ
  読み書きすると「up → look up」が文脈なしの正規化結果として残ってしまう（汚染）。
  読みも書きも完全に分離する。
- 新テーブル `word_context_normalizations`:
  `UNIQUE(input, context_hash, target_language)`。`context_hash` は
  trim + 連続空白畳み + 小文字化した文脈の sha256。デバッグ用に context 原文も保存する。
- 文脈なし呼び出しは従来どおり既存テーブル（回帰なし）。
  ログ（`word_normalize_requests`）はスキーマ変更せず、logger 行に文脈有無だけ出す。

### 制約（記録）

- タップ語そのものが登録済みの場合の最速パス（正規化なしで詳細へ遷移）は従来どおり維持する。
  例: 「up」を単語として登録済みだと、文中の「up」タップは熟語提案にならず「up」詳細へ飛ぶ。
  （最速パス・オフライン動作の維持を優先。問題になれば後続で検討）
- backend の context は 300 字でクランプ。iOS 側の切り出し上限 240 字とあわせて二重に防ぐ。

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
- [x] Phase 2: AI 情報生成のフレーズ対応（backend wordInfo プロンプト）（2026-07-11）
  - `wordInfo.ts`: 入力にスペースを含むときだけフレーズ指示ブロックをプロンプトに追加
    （品詞=句動詞/熟語、inflections=中心動詞を活用させたフレーズ全体、IPA=フレーズ全体を
    1組のスラッシュで囲む、syllables=null、分離可能句動詞は usageNote/commonMistakes）。
    1語のプロンプトは従来と同一（回帰リスクなし）。スキーマは description の追記のみ。
  - 実測時「by heart」の IPA が `/baɪ/ /hɑːrt/` と語ごとに囲まれて揺れたため、
    「1組のスラッシュで囲む（語ごとに囲まない）」と明記して安定化。
  - 実測結果（regenerate:true）: `look up`→句動詞 / /lʊk ʌp/ / looks up 等4活用 /
    usageNote に分離可能の説明、`take care of`→句動詞 / 活用4件、`by heart`→熟語 /
    /baɪ hɑːrt/ / 活用なし、`run`→動詞（1語の回帰OK）。backend テスト16件緑。
  - iOS 側変更なし（partOfSpeech は文字列そのまま表示）。
- [x] Phase 3: クイズ生成のフレーズ対応（supportsPhrase ガード + イラスト品質の実測判断）（2026-07-11）
  - `quizQuestions.ts`: `FormatSpec.supportsPhrase?`（省略時 true、vc2 のみ false）を追加し、
    形式フィルタを `availableFormatSpecs(word, info)`（エクスポート・単体テスト対象）に切り出し。
  - **既存バグ修正（tc7 の素材ゲート全滅）**: 2026-07-04 の bad7982 で wordInfo の
    inflections[].form が英語ラベル化されたが、`INFLECTION_FORM_EN`（日→英マップ）が未追従で、
    それ以降に生成した単語情報では tc7 が黙って生成されなくなっていた。
    `englishInflectionForm`（日本語はマップ・英語ラベルはそのまま通す）で新旧両対応に修復。
  - 実測（regenerate:true）: `look up` で 21 問生成・vc2 なし・tc7 成立
    （"What is the past tense of \"look up\"?" / looked up 等4択）・tc6/vc4/vt1/vtt1 の
    正解や acceptedAnswers も "look up" で成立（correctMustBeWord 通過）。
  - **イラスト品質の判断: 熟語もイラスト対象のまま（除外しない）**。gpt-image-2 実測で
    `look up`（辞書を指差し+疑問符）・`by heart`（本を閉じて暗唱）とも意味が伝わる品質。
    定義+例文がプロンプトに入るためフレーズでも文脈が効く。ic1/it1 のルール生成も
    フレーズで動作確認（選択肢にフレーズ+単語混在、acceptedAnswers=["look up"]）。
  - iOS 変更なし（FormatSelector の availableFormats はサーバ保存問題の形式一覧なので、
    生成されない vc2 は出題されない）。backend 単体テスト 21 件緑
    （availableFormatSpecs のフレーズゲート・活用形ラベル新旧互換を追加）。
- [x] Phase 4: 本文タップからの熟語登録（案 A: 文脈から熟語自動判定）（2026-07-11）
  - backend: `word_context_normalizations` テーブル（`UNIQUE(input, context_hash, target_language)`、
    `contextHashKey` = trim+空白畳み+小文字化の sha256）を新設し、文脈付き呼び出しは
    読み書きとも既存キャッシュと完全分離。`wordNormalize.ts` に `phrase_part` status と
    文脈指示ブロック（文脈がある時だけ）を追加。`/api/word-normalize` に `context` パラメータ
    （300字クランプ）。
  - iOS: リンク URL に位置情報（`o`=オフセット、`b`=ブロック番号）を追加し、タップ時に
    `EnglishWordLink.sentenceContext`（境界=`.!?`+空白/改行、240字上限で語中心ウィンドウ）で
    文を切り出して `WordTapAction(word, context:)` → `decide(context:)` → API へ素通し。
    `WordNormalizeStatus.phrasePart`（suggestsCorrection=true）追加で既存確認ダイアログが
    そのまま機能。手動入力（WordAddView）・Correct Word は context=nil で従来どおり。
  - 実測（curl・regenerate:true）: 「up」+「I looked it up yesterday.」→ phrase_part/`look up`、
    「care」+「She takes care of her brother.」→ phrase_part/`take care of`、
    「up」+「She gave up smoking.」→ phrase_part/`give up`（同語・別文脈が別キャッシュ行）、
    「yesterday」→ canonical、「He looked tired.」の「looked」→ inflected/`look`。
    文脈なし回帰: `up`→canonical（汚染なし）・`ran`→`run`・`look up`→phrase。
  - 実測（シミュレータ E2E）: Writing の添削ラウンド本文「I looked it up yesterday.」の
    「looked」タップ → 確認ダイアログ「文中の『looked』は句動詞『look up』の過去形…」→
    Register “look up” で登録 → AI 情報・クイズ 21 問（vc2 なし）がフレーズキャッシュから連鎖取得。
    保存された context が画面上の文と完全一致することを DB で確認。
    （タップ語自体が変化形のときは LLM が status=inflected で lemma=フレーズを返すことがあるが、
    inflected も確認ダイアログを出すため UX は同一。）
  - テスト: iOS 単体 120 件緑（sentenceContext・URL 往復・phrase_part デコード/確認判定・
    context 素通し・スタブ）。backend 21 件緑。UI テスト（WordAdd 正規化・訂正・レッスン語追加）緑。

## 留意点

1. ハイフン語との同一性（`check in` と `check-in`）は別語のまま扱う（正規化 LLM の lemma に寄せる）。
   問題が出たら正規化プロンプトで統一方針を決める。
2. 文脈付き正規化のキャッシュ設計（`UNIQUE(input, target_language)` が文脈で崩れる）は
   Phase 4 着手時に決める（5-(b) 参照）。
