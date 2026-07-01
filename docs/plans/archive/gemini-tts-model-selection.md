# Gemini TTSモデル（Flash/Pro）の選択機能

## 目的・背景

[archive/gemini-tts-voice-selection.md](archive/gemini-tts-voice-selection.md) でGemini TTS
（`backend/src/tts.ts`）による音声読み上げと声のタイプ（ちょビ/なるこ）選択を実装済み。
現状はモデルが`GEMINI_TTS_MODEL`環境変数（既定`gemini-2.5-flash-preview-tts`固定）で、
アプリ側からの切り替えはできない。

Geminiにはより高品質な`gemini-2.5-pro-preview-tts`もあるため、声のタイプと同様に
設定画面からモデル（Flash=高速・Pro=高品質）を選べるようにする。

## 対応方針

- `backend/src/tts.ts`
  - `MODEL_PRESETS`（`flash` → `gemini-2.5-flash-preview-tts`, `pro` → `gemini-2.5-pro-preview-tts`）
    を声のプリセットと同様の形で追加
  - `synthesizeSpeech(text, voiceKey, modelKey)`にモデル引数を追加し、
    エンドポイントURLの組み立てに使う
  - `config.geminiTtsModel`/`GEMINI_TTS_MODEL`環境変数はモデル選択がリクエスト単位になるため削除する
    （声のタイプと同じくハードコードされた2択のプリセットに統一し、環境変数と二重管理にしない）
- `backend/src/index.ts`
  - `POST /api/tts`のリクエストボディに`model: "flash" | "pro"`を追加し、`voice`と同様にバリデーション
- `backend/.env.example`: `GEMINI_TTS_MODEL`の記載を削除
- iOS
  - `Sources/Support/AppSettingsKeys.swift`に`ttsModel`（既定`"flash"`）を追加
  - `Sources/Views/SettingsView.swift`の「音声読み上げ」Sectionに
    Picker「TTSモデル」（高速 / 高品質）を追加（Gemini選択時のみ有効）
  - `Sources/Services/GeminiSpeechService.swift`の`speak`に`model`引数を追加しリクエストボディに含める
  - `Sources/Views/PhotoDetailView.swift`で`ttsModel`を読み、`geminiSpeechService.speak`に渡す

## 影響範囲

- 変更: `backend/src/tts.ts`, `backend/src/index.ts`, `backend/src/config.ts`, `backend/.env.example`,
  iOS側 `AppSettingsKeys.swift` / `SettingsView.swift` / `GeminiSpeechService.swift` / `PhotoDetailView.swift`
- 新規ファイルなし、DBスキーマ変更なし

## テスト方針

- バックエンド: `tsc`ビルド確認、`curl`で`model=flash`/`model=pro`それぞれ200 & audio/wavが返ることを確認
- iOS: `xcodebuild`でのシミュレータ向けビルド成功を確認
- 実機での聴き比べ（Pro版の音質向上確認）はユーザー側で実施を依頼する
