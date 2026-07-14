# 穴埋め形式（vtt1/tc3/tc6）で空欄が無い不良問題を弾く

## 目的・背景

復習クイズの `vtt1`（例文リスニング穴埋め入力）で、`displayText` が音声（`audioText`）と
まったく同じ完全文になり、空欄 `_____` が無いまま出題される不良が報告された
（実例: 単語 "consolidate"、iOS の出題画面で空欄なし・答えが露出）。

- `vtt1` はタイプ入力形式のため、空欄が無い＝答えが本文に直書き＝問題として成立しない。
- 根本原因は **AI 出力の検証漏れ**。`_____` を入れる指示はプロンプト（`quizQuestions.ts`
  の `vtt1`/`tc3`/`tc6` promptSpec）にしか無く、`validateAndConvert` は
  `displayText` が空でないか（`needsDisplayText`）しか見ておらず、空欄の有無を検証していない。
  AI がまれに空欄化に失敗した完全文を返すと、そのまま保存・出題される。
- 同じ `_____` 依存形式の `tc3`（例文穴埋め4択）・`tc6`（コロケーション4択）も同じ検証漏れを持つ
  （4択なので実害は vtt1 ほど致命的ではないが、答え露出のリスクは同じ）。

ローカル DB（`backend/data/db.sqlite`）の保存済み vtt1 全24件は全て空欄ありで正常だった。
不良は間欠的な AI 失敗であり、`consolidate` はローカルには無い（別バックエンドで遭遇）。
そのため修正は「再発防止（検証ガード）＋既存不良データの一掃」の2段構えとする。

## 対応方針

### Phase 1: 生成時の検証ガード（再発防止）

- `FormatSpec` に `needsBlank?: boolean` を追加し、`tc3`/`tc6`/`vtt1` を `true` にする。
- `validateAndConvert` に「`needsBlank` 形式は `displayText` に空欄（連続アンダースコア）が
  無ければ `null` で捨てる」チェックを追加する。判定は `/_{3,}/`（3文字以上連続の `_`。
  プロンプトの `_____` は5文字だが 3〜4 のブレも許容）。
- ユニットテスト（`backend/test/quizQuestions.test.ts`）に、空欄なし vtt1 が捨てられ・
  空欄あり vtt1 が受理されるケースを追加する。

### Phase 2: 既存不良データの起動時クリーンアップ

- `db.ts` の起動時クリーンアップ（tt2 削除等と同じ場所）に、
  `tc3`/`tc6`/`vtt1` で `displayText` に空欄が無いレコードを DELETE する処理を追加する（冪等）。
  判定は SQLite の `GLOB '*___*'`（`_` は GLOB では文字リテラル。3連続アンダースコアの有無）。
- 削除後、その単語に他形式の問題が残っていれば iOS の自己修復トリガは走らないため、
  当該形式は次回の全再生成（管理画面 regenerate）で作り直されるまで欠ける。
  出題が壊れる状態は消えるので優先度としては許容し、その旨をコメントに残す。

## 影響範囲

- `backend/src/quizQuestions.ts`（`FormatSpec` / 3形式の spec / `validateAndConvert`）
- `backend/src/db.ts`（起動時クリーンアップ1文追加）
- `backend/test/quizQuestions.test.ts`（テスト追加）
- iOS 側は変更なし（`displayText` を素通し描画しているだけで、不良は保存データ側）。

## テスト方針

- `cd backend && npm test`（既存＋追加テストが全パス）。
- `npm run build`（tsc 型チェックが通る）。
- ローカル DB でクリーンアップ SQL を dry-run（SELECT）して、
  誤って正常データを消さないこと（現状ローカルは0件該当）を確認する。
