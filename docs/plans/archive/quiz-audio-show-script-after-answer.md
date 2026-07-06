# 単語出題の音声読み上げ解答後に英文を表示する

## 目的・背景

復習クイズの音声出題形式（VC1〜VC8 / VTC1 / VTT1 / VT1 / VT2 など、`promptBucket == .audio`）は、
英文を表示せず音声だけで出題する（リスニング）。純リスニング形式（VC*・VT*）は `displayText` が
nil のため、ユーザーは何と読み上げられたのかを最後まで確認できない。

解答後に読み上げられた英文（`ReviewQuestion.audioText`）を表示し、聞き取れなかった内容を
目で確認して記憶を補強できるようにする。

## 対応方針

- `ReviewSessionView.questionView` の Play Audio ボタン直下に、解答済み（`feedback != nil`）かつ
  `audioText` を持つ問題のとき、読み上げられた英文を表示するビューを追加する。
- 英文は `TappableEnglishText` で表示し、単語タップ登録に対応させる。
- Play Audio ボタンの真下に置くことで「もう一度聞く → 英文を読む」を同じ場所で完結させる。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/ReviewSessionView.swift` のみ（表示追加）。
- データモデル・サーバAPIの変更なし。`audioText` は既存フィールド。

## テスト方針

- ビルドが通ること。
- 音声出題（VC 系）で解答後に読み上げ英文が表示されること（実機/シミュレータで確認）。
- 非音声出題では従来どおり表示が変わらないこと。
