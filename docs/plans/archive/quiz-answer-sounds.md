# 単語クイズ 正誤サウンド

## 目的・背景
単語クイズ（Review セッション）の解答時に、正解では気持ちいい音、不正解ではそれとない控えめな音を鳴らし、学習のフィードバックを心地よくする。あわせてハプティック（success / warning）も付与する。

## 対応方針
- 音源は**音声ファイルを同梱**する方式（ユーザー選択）。
  - 高品質なチャイム/ブリップを macOS 上でプログラム合成し、`.caf`（LEI16）として生成する。
    - `correct.caf`: 明るい上昇アルペジオのベルチャイム（C6→E6→G6→C7 系）
    - `wrong.caf`: 低めで柔らかい短いブリップ（控えめ・低音量）
  - 生成スクリプトは `ios/tools/generate_quiz_sounds.py` に残し、再生成できるようにする。
- 配置: `ios/ESLLearningAssistant/Resources/Sounds/correct.caf`, `wrong.caf`。
  - `project.yml` の `Resources` パスは XcodeGen が自動でリソース取り込みするため、置くだけでバンドルされる（pbxproj 手編集不要、`xcodegen generate` で再生成）。
- 再生層: `Sources/Services/SoundEffectService.swift` を新規追加。
  - `AVAudioPlayer` を用い、正解/不正解のプレイヤーを事前ロードしておき低遅延で再生。
  - オーディオセッションは `.ambient`（他再生を止めない・消音スイッチ尊重）を基本に、TTS と競合しない形にする。`TTSPlaybackService` は `.playback` を使うため、効果音は独自プレイヤーで短時間再生する。
  - ハプティックは `UINotificationFeedbackGenerator`（.success / .warning）。
- 呼び出し: `ReviewSessionView.recordAnswer(isCorrect:)` の分岐で `isCorrect` に応じて再生（全クイズ形式がここに集約されている）。

## 影響範囲
- 新規: `SoundEffectService.swift`, `Resources/Sounds/*.caf`, `tools/generate_quiz_sounds.py`
- 変更: `ReviewSessionView.swift`（サービス保持 + recordAnswer で再生）, `ESLLearningAssistant.xcodeproj`（xcodegen 再生成）
- 既存の TTS 再生（`ttsPlayback` / `speechService`）とは別プレイヤーのため相互干渉を避ける。

## テスト方針
- `xcodegen generate` 後にビルドが通ること。
- 実機/シミュレータでクイズを解き、正解/不正解でそれぞれ音とハプティックが鳴ること（消音時はハプティックのみ）。
- TTS 読み上げ中でも効果音がアプリをクラッシュさせないこと。
