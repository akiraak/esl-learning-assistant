# 単語出題で自動読み上げを行わない

## 目的・背景

復習クイズ（`ReviewSessionView`）の音声出題では、問題表示と同時に音声を1回自動再生している。
これをやめ、再生ボタンのタップ時のみ音声を再生するようにする。

## 対応方針

`ReviewSessionView.advance()` 内の、出題表示時に音声を自動再生している箇所を削除する。

- 該当: `ios/.../Views/ReviewSessionView.swift` の `advance()`
  ```swift
  // 音声出題は表示と同時に1回自動再生する
  if let audioText = question.audioText {
      playAudio(audioText)
  }
  ```
- 手動再生ボタン（`audioReplayButton` → `playAudio`）は既に存在するため、これはそのまま残す。

## 影響範囲

- `ReviewSessionView.swift` のみ。音声出題形式（`audioText` を持つ問題）で、出題時に自動再生されなくなる。
- ユーザーは「Play Audio」ボタンを押して聞く。

## テスト方針

- ビルドが通ること。
- 音声出題が表示されても自動で鳴らず、ボタンタップで再生されることを確認。
