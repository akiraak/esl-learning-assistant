# 単語詳細の Word Forms の左項目名を英語にする

## 目的・背景

単語詳細画面の Word Forms セクションで、左側の項目名（変化の種類）が「三人称単数現在形」「過去形」「過去分詞」「現在分詞」など日本語（母語）で表示されている。英語学習アプリとして、他セクション見出し（Word Forms / Examples 等）と同様に英語表記に統一する。

ラベルは AI 生成時に決まる。`backend/src/wordInfo.ts` の structured output スキーマで `inflections[].form` を「変化の種類（母語。例:「過去形」）」と指示しているため、日本語で生成・保存されている。

## 対応方針

### Step 1: backend の生成プロンプトを英語ラベル指定に変更

- `backend/src/wordInfo.ts` の `form` の description を英語ラベル指定に変更する
  - 例: `"変化の種類（英語の文法用語で。例: \"past tense\", \"past participle\", \"third-person singular\", \"present participle\", \"plural\", \"comparative\", \"superlative\"）"`
- `npm run build` で `backend/dist/` を再生成する

### Step 2: iOS 側で既存データの日本語ラベルを英語に変換して表示

既に生成済みの単語データには日本語ラベルが保存されているため、表示時に既知の日本語ラベルを英語へマッピングする（未知のラベルはそのまま表示）。

- `ios/ESLLearningAssistant/Sources/Views/WordDetailView.swift` の Word Forms セクションで `inflection.form` を変換して表示するヘルパーを追加
- マッピング対象（想定される日本語ラベル）:
  - 三人称単数現在形 / 三人称単数 → third-person singular
  - 過去形 → past tense
  - 過去分詞 → past participle
  - 現在分詞 → present participle
  - 動名詞 → gerund
  - 複数形 → plural
  - 比較級 → comparative
  - 最上級 → superlative
  - 原形 → base form

## 影響範囲

- `backend/src/wordInfo.ts`（＋ `dist/` 再ビルド）: 新規生成される単語情報の form が英語になる
- `ios/.../WordDetailView.swift`: 表示のみの変更。保存データは変更しない
- 単語クイズ等は `inflections` を使っていないため影響なし

## テスト方針

- backend: `tsc` ビルドが通ることを確認
- iOS: 既存テスト（`WordAIInfoTests` はデコードのみで form の値に依存）を含め `xcodebuild test` が通ることを確認
- 表示確認: 日本語ラベル入りの既存データが英語で表示されること（マッピングのユニットテストを追加）
