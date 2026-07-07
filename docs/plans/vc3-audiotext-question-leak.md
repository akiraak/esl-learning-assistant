# 修正: audioText に設問文が混入する（vc3 ほか音声形式）プロンプト堅牢性バグ

## 目的・背景
- クイズの音声形式で、TTS 読み上げ用の `audioText` に本来含めるべきでない
  **設問・問いかけ**が混入することがある。
- 実データで確認（`quiz_questions`, ja）:
  - `vc3` "experience" v0: `"... for a long time. What word is this?"`
  - `vc3` "experience" v2: `"... do something. This is the verb form. Which word is it?"`
- 設問は `instruction`（例: "Listen to the definition. Which word does it describe?"）が
  担うべきで、`audioText` は読み上げ本文のみであるべき。混入すると読み上げに設問が混じり
  「読み上げがおかしい」症状になる。[[lazy-tts-reading-investigation]] の副産物として発見。

## 原因
- `backend/src/quizQuestions.ts` の生成プロンプトに「audioText に設問・指示を含めない」
  という明示制約が無く、モデルが `instruction` 相当の問いかけを `audioText` にも付けることがある。
- 特に `vc3`（audioText=英語定義）で発生。定義の後に "What word is this?" を足しがち。

## 対応方針
1. `buildPrompt` の共通ルールに、全音声形式へ効く制約を追加:
   「audioText は読み上げ本文そのものだけ。設問・問いかけ・指示（例:「What word is this?」）や
   instruction と重複する文言を含めない」。
2. `vc3` の `promptSpec` を「定義文のみ。問いかけを付けない」と明確化。

## 影響範囲
- `backend/src/quizQuestions.ts` のみ（プロンプト文言）。スキーマ・検証・iOS は不変。
- 効果は**新規生成**にのみ及ぶ。既存の生成済み問題（本番の "experience" 等）は
  管理画面のクイズ再生成で作り直せば解消する（別アクション）。

## テスト方針
- ローカル実キーで、既知の再現語 "experience"（＋対照 "achievement"）の quiz を複数回生成し、
  `vc3` の audioText に設問・"?" が含まれないことを確認する。
- 非決定性のため 100% 保証はできないが、修正前後で混入率が下がることを確認する。
