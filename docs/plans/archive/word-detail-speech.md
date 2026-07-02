# 単語詳細の英文読み上げ（iOS 組み込み TTS）

## 目的・背景

- `TODO.md`: 「単語詳細の英文部分に読み上げを入れる。ios組み込みの機能を使う」
- 単語詳細画面（`WordDetailView`）には英語の例文が表示されるが、音声で確認する手段がない。
- 既に `SpeechService`（`AVSpeechSynthesizer` ラッパー、端末内蔵 TTS）が存在し、`PhotoDetailView` の OCR 本文読み上げで使用実績がある。これを再利用する。

## 対応方針

- `WordDetailView` に `@StateObject` で `SpeechService` を 1 つ持ち、読み上げ中のテキストを `@State speakingText: String?` で管理する。
- 読み上げボタン（スピーカーアイコン、再生中は stop アイコン）を英文の行末に付ける。対象:
  1. **Pronunciation セクション**: 見出し語（`word.text`）自体の発音
  2. **Examples セクション**（AI 生成情報）: 各例文の `example.english`
  3. **Example Sentence セクション**（レガシー例文）: `word.exampleSentence`
- 同じテキストのボタンを再タップで停止。別テキストをタップすると切り替え（`SpeechService.speak` は再生中なら停止してから話すので既存挙動で足りる）。
- 画面離脱時（`onDisappear`）に停止する（`PhotoDetailView` と同じ作法）。
- Gemini TTS は使わない（TODO の指定どおり端末内蔵のみ）。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/WordDetailView.swift` のみ（`SpeechService` は変更なし）。

## テスト方針

- `xcodebuild` でビルドが通ることを確認する。
- TTS の実音声はシミュレータ GUI 操作が必要なため、ボタン表示・状態切り替えロジックのコードレビューで担保する。
