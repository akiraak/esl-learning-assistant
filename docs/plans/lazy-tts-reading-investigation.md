# 調査: "lazy" のAI生成読み上げがおかしい / 生成プロンプトの検証

## 目的・背景
- 単語 "lazy" の AI 生成音声（Gemini TTS）の読み上げがおかしい、という報告。
- TODO: `lazy のAI生成読み上げがおかしい。生成プロンプトを検証`
- 「生成プロンプト」= TTS に投げる際のプロンプト、および audioText を生成する AI プロンプトの両方を検証する。

## これまでに判明した事実（調査ログ）
1. **音節/IPA 形は TTS に渡っていない**（iOS 側を全走査して確認）。
   - 単語詳細の発音ボタンは `TTSButton(text: word.text)` で、素の単語 "lazy" を送る。
   - 音節形 "LA-zy"（強勢を大文字）や IPA `/ˈleɪ.zi/` は画面表示専用（`WordDetailView.swift:346-348`）で TTS には渡らない。
   - → 「音節形が読み上げられている」説は棄却。
2. **TTS は素のテキストをそのまま合成**（`backend/src/index.ts` `/api/tts`、`ttsStore.ts`、`tts.ts`）。
   - ただし合成時に **スタイル指示を前置き**している:
     `contents:[{parts:[{text: `${preset.style}: ${chunk}`}]}]`（`tts.ts:118`）
   - 例（chobi）: `"Read the following in a warm, gently cheerful, smiling tone: lazy"`
3. **有力仮説**: "lazy" は **それ自体が「気だるい/ゆっくり」を表す manner 形容詞**。
   `"...tone: lazy"` の末尾に置かれると、モデルが "lazy" を
   **読み上げる語**ではなく **追加のスタイル指示**（気だるいトーンで読め）と解釈しうる。
   "apple"/"banana" のような具体名詞では起きにくく、"lazy" 特有の症状と整合する。
   同種のリスク語: slow, quiet, loud, soft, angry, sad, cheerful, calm, sleepy 等。
4. 副次発見（別バグ、audioText 生成プロンプトの堅牢性）:
   - `vc3`（定義読み上げ）で、audioText に本来含めない設問文
     "What word is this?" / "Which word is it?" が混入した例が実データに存在
     （`quiz_questions` の "experience" v0/v2）。読み上げに設問が混じる = これも「読み上げがおかしい」の一種。
   - `tts_audio` キャッシュに空所付き文 "I eat a _____ every morning..." が残存（旧世代の名残。現行 quiz_questions には無し）。

## 検証方針（再現）
- ローカル `.env` に実キーあり。Gemini TTS → 生成 WAV → Gemini STT で書き起こし、
  **意図した語と一致するか**を客観指標にする（耳で聞かずに判定できる）。
- 比較条件:
  - A) 現行プロンプト `"{style}: lazy"`
  - B) 対照 `"{style}: apple"`（正常系）
  - C) 修正案プロンプト（"lazy" をスタイルと誤認させない構造）
- リスク語（slow/quiet 等）も併せてサンプルし、単発でなく構造的問題か確認する。

## 再現結果（2026-07-06 実測）
ローカル `.env` の実キーで再現。手法: Gemini TTS → 生成WAV → Gemini STT 書き起こし + 尺計測。
1. **内容生成プロンプトは "lazy" で正常**。`generateWordInfo` / `generateQuizQuestions` を実行 →
   定義・例文・全 audioText がすべて自然で正しい（設問文混入なし・空所なし）。
   - pronunciation: `{"ipa":"/ˈleɪ.zi/","syllables":"LA-zy"}`（表示専用、TTS 未使用）。
2. **素の "lazy" の TTS は概ね正常だが、まれに不明瞭**。両ボイス各4サンプル計8回中:
   - 7回は "Lazy" と正しく書き起こし、尺も正常（~1.1–1.5s）。
   - **1回（Aoede/naruko）が "Lacy" と書き起こされた**（/z/ が /s/ に濁らず不明瞭）。
   - → 体系的なプロンプト不具合ではなく、**合成の非決定性による散発的な不明瞭**。
   - 定義文・例文の読み上げは両ボイスとも正常。
3. **根本原因の本命 = 恒久キャッシュ**。`tts_audio` は `sha256("model|text")` キーで
   **一度合成した音声を無効化せず永久に返す**（`ttsStore.ts:21-44`）。ボイスは初回にランダム固定。
   → 初回合成がたまたま不明瞭だと、その "lazy" 音声が**恒久的に**配信され続ける。
   これは**プロンプト修正では直らない**（該当キャッシュのパージ/再合成が必要）。
   - 救済策は既存: 管理画面 `/admin/tts` に個別削除（`deleteTtsAudio`, `admin.ts:1300`）あり。
     該当 "lazy" を削除 → 次回リクエストで再合成される。

## 結論
- 「生成プロンプト」自体に "lazy" 固有の不具合は無い（内容・音声とも再現テストでほぼ正常）。
- ユーザーが聞いた「おかしい読み上げ」の最有力は、**初回合成でたまたま不明瞭になった "lazy" の
  音声が恒久キャッシュに固定されている**こと。まず `/admin/tts` で該当を削除し再合成を促すのが確実。
- 併せて、同機能で実在した**プロンプト堅牢性の別バグ**（`vc3` の audioText へ設問文混入）は
  読み上げ品質に直結するため、別途修正候補とする。

## 対応方針（想定）
- TTS の前置きプロンプトを、内容語をスタイル指示と混同しない構造へ変更する。
  例: 読み上げ対象を明示ラベル/改行で分離し「次の内容をそのまま発音」する指示にする。
- あわせて audioText 生成プロンプト（vc3 等）に「設問文を audioText に含めない」制約を明記。

## 影響範囲
- `backend/src/tts.ts`（`synthesizeChunk` の prompt 構築）。
- キャッシュキーは `sha256("model|text")` で **text（=audioText）** のみ。前置きスタイル文は
  キーに含まれないため、プロンプト構造変更ではキャッシュは無効化されない（＝既存キャッシュは残る）。
  修正効果を全単語に反映するには TTS キャッシュのパージ（該当語 or 全体）が別途必要。
- audioText 側を直す場合は `backend/src/quizQuestions.ts` と、生成済み `quiz_questions` の再生成。

## 追加検証: 「単語の単体読み上げだけ再生成する機能」の実現可否（2026-07-06）

### 「単体読み上げ」の実体
- `tts_audio` の `text` == 単語そのもの（例 "lazy"）の行。用途:
  - iOS 単語詳細の発音ボタン `POST /api/tts {text:"lazy", model:<flash|pro>}`
  - クイズ vc1/vc2/vc5/vt1/vc8 の audioText（== 単語）
- 定義・例文の音声（`text` == 定義文/例文）は対象外（＝この機能では触らない）。

### 既存の近い機能
- `/admin/tts`（TTS一覧, `admin.ts:913-975`）に**個別削除**あり（`deleteTtsAudio`）。
  削除すれば次回リクエスト時に再合成される＝**8割方これで解決可能**。
- 不足点: (a) 単語単位で狙って消しにくい（テキスト検索が要る）、(b) 遅延再合成のため
  「作り直した音を今すぐ試聴」ができない、(c) ボイスは初回ランダム固定のまま。

### 設計案（推奨: 管理画面・単語詳細に「読み上げ音声を再生成」ボタン）
- UI: `/admin/words/:id`（`admin.ts:757-806`）の action-buttons に1つ追加。
  既存の「再生成（AI情報）」「削除」と並べる。任意で現在の単語音声の `<audio>` 試聴も併設。
- ルート: `POST /admin/words/:id/regenerate-audio`
  - `row.word` について、キャッシュに存在する各モデル（flash/pro）の行を
    **ファイル削除 + `deleteTtsAudio(id)`** → **即時 `getOrSynthesizeTtsAudio(word, model)` で再合成**。
    （どちらも未キャッシュなら flash を1件生成）。
  - 実装は `ttsStore.ts` に薄い `regenerateTtsAudio(text, model)` を足すのが素直
    （hash 算出ロジックが既にそこにあるため）。
- 影響: `backend/src/ttsStore.ts`（+~12行）, `backend/src/admin.ts`（ボタン+ルート ~40行）。
  iOS 変更・アプリ再リリース不要。DB スキーマ変更なし。
- 費用: 1回の再合成のみ（flash は安価）。ボイスはランダムなので、まだ不明瞭なら再クリックで再抽選。
- 限界: 再合成が明瞭になる保証は無い（非決定性、~12%が不明瞭）。品質自動判定
  （STT ラウンドトリップで明瞭になるまでリトライ）は過剰なので当面は手動リトライで割り切る。

### 実現可否の結論
- **実現可能・低コスト・低リスク**。推奨は管理画面ボタン方式（Option 1）。
- iOS 側の force-refresh（`/api/tts` に `force` 追加 + 長押し再生成）は、
  エンドユーザーに課金合成を踏ませる点とアプリ再リリースが必要な点で、当面は非推奨。

## テスト方針
- 再現スクリプトで A/B/C の STT 一致率を比較（修正案 C で一致することを確認）。
- リスク語群でリグレッションが無いこと（apple 等が引き続き正常）。
