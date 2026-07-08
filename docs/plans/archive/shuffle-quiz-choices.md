# 選択肢の正解位置をサーバ側で必ずシャッフルする

## 目的・背景

復習クイズの多肢選択問題で、正解の選択肢が並び順の中で固定位置になりうる問題がある
（TODO「選択肢の正解の順番が必ず固定なものがあるかチェック」の調査結果）。

調査で判明した点（生成元は `backend/src/quizQuestions.ts` の1ファイルのみ。iOS・保存・
表示側はどこも選択肢を並べ替えず、サーバの `correctIndex` をそのまま使う）:

- 🔴 **tc8（品詞当て）**: `options` を必ず `["noun","verb","adjective","adverb"]` の固定順で
  生成し、3バリエーションとも同一。正解位置が単語の品詞で確定する（名詞なら常に先頭）。
- 🟠 **AI 生成4択全般（tc1–tc10 / vc1–vc7 / vtc1）**: `validateAndConvert` が LLM の返した
  `correctIndex` を無シャッフルでそのまま保存。LLM の位置バイアスで正解位置が偏りうる。
- 🟢 **イラスト系（tc11 / vc8 / ic1）**: 既存の `shuffledChoices`（Fisher–Yates）で毎回
  ランダム化済み。問題なし。

## 対応方針

修正はバックエンド1箇所に集約する。`validateAndConvert`（`backend/src/quizQuestions.ts`）の
`answerType === "choices"` 分岐で、検証を通過した `options` / `correctIndex` を保存する前に、
既存の `shuffledChoices()` と同じ仕組みで**必ず再シャッフルして正解位置を振り直す**。

- イラスト系と全く同じ挙動になり、tc8 も含めて全4択形式が一律に「正解位置ランダム」になる。
- 選択肢の文字列自体は変更せず（トリム等の既存挙動も変えない）、並び順だけ入れ替える。
- tc8 のプロンプト（`options は必ず [...] の4つ（この順）`）はそのまま残す。LLM に4品詞を
  過不足なく出させるための指示であり、最終的な表示位置はサーバのシャッフルが担保する。

## 影響範囲

- `backend/src/quizQuestions.ts` の `validateAndConvert`（choices 分岐）のみ。
- 既存ヘルパ `shuffledChoices` / `pickRandom` を再利用（関数宣言なので巻き上げで先に呼べる）。
- `admin.ts:1932` は保存済み `correctIndex` に ✓ を付けて表示するだけで順序非依存 → 影響なし。
- iOS 側は `options` / `correctIndex` をそのままデコード・表示するだけ → 影響なし。
- 保存済みの既存問題（すでに DB にある question_json）は再生成されるまで従来の並びのまま。
  今後生成される問題から正解位置がランダム化される。

## テスト方針

- バックエンドに自動テストは無い。`npx tsc --noEmit` で型・コンパイルを確認する。
- `validateAndConvert` に同一 `options`/`correctIndex` を複数回通し、正解の文字列が保たれ、
  かつ位置が分散することを一時スクリプトで確認する（`options[correctIndex]` が元の正解と一致）。
