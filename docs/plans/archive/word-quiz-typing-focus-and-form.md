# 単語問題テキスト入力：自動フォーカスとフォーム改善

## 目的・背景

復習クイズのテキスト入力形式（`ReviewQuestionAnswer.typing`）で、以下 2 点を改善する。

- [ ] 問題表示時にテキストフィールドへ最初からフォーカスを当て、すぐ入力できるようにする
- [ ] テキスト入力フォームを見た目・役割の分かりやすいものにする

現状（`ESLLearningAssistant/Sources/Views/ReviewSessionView.swift`）：
- `typingArea(_:)`（L321-344）は素の `TextField("Type your answer", …)` + "Answer" ボタンのみ。
- `@FocusState isAnswerFieldFocused`（L56）は submit 時に `false` にするだけで、`true` にする箇所が無い＝自動フォーカスされない。

## 対応方針

### 1. 自動フォーカス
`advance()`（L608-632）で次の問題を `current` に設定した後、その問題が `.typing` の場合にだけ、
わずかな遅延を挟んで `isAnswerFieldFocused = true` にする。
- TextField がまだ描画されていないタイミングで即時に立てても効かないため、`Task { @MainActor }` +
  `Task.sleep` で ~0.3s 遅延させてから立てる（typing → typing 連続でも `.onAppear` に依存せず確実）。

### 2. フォーム改善
`typingArea(_:)` を作り直す。
- 「Type your answer」ラベルを見出しとして上部に表示。
- フィールドを角丸カードで囲み、pencil アイコンを添え、フォーカス中はアクセントカラーの枠線を表示。
- 単一行 TextField（`axis: .vertical` を外す）にして Return キーで送信できるよう
  `.submitLabel(.go)` + `.onSubmit`。
- "Answer" ボタンは `controlSize(.large)` で押しやすく。
- 既存の accessibilityIdentifier（`reviewTypedAnswerField` / `reviewSubmitButton`）は維持し UITest を壊さない。

## 影響範囲
- `ESLLearningAssistant/Sources/Views/ReviewSessionView.swift` のみ（`typingArea` と `advance`）。
- モデル・判定ロジック（ReviewQuestion.swift 等）は変更しない。

## テスト方針
- ビルドが通ること。
- 既存 UITest（`ReviewSessionUITests`）の identifier 依存が壊れないこと。
- 実機/シミュレータでテキスト問題出題時にキーボードが自動表示され、Return で送信できること。
