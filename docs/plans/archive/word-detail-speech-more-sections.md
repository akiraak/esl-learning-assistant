# 単語詳細の読み上げ対象拡大（Meanings / Collocations / Synonyms & Antonyms）

## 目的・背景

- [word-detail-speech](archive/word-detail-speech.md) で Pronunciation・Examples・Example Sentence に
  読み上げボタンを追加した。その追補として、残りの英文セクションにも読み上げを付ける。

## 対応方針

既存の `SpeechButton`（端末内蔵 TTS）を以下にも配置する。

1. **Meanings**: 各語義の英英定義 `sense.englishDefinition` を読み上げ（母語訳 `meaning` は対象外）
2. **Collocations**: 各コロケーション行を読み上げ
3. **Synonyms & Antonyms**: Synonyms 行・Antonyms 行それぞれのカンマ区切りリストを読み上げ

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/WordDetailView.swift` のみ。

## テスト方針

- `xcodebuild` でシミュレータ向けビルドが通ることを確認する。
