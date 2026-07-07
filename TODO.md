# TODO

- [ ] Audio の英文文字起こしと日本語翻訳 [plan](docs/plans/audio-transcription-translation.md)
  - [x] Phase 1: バックエンド — 文字起こしAPI（Gemini 音声→英文 ＋ 既存 translateText で英→日、`POST /api/transcribe-translate`）
  - [x] Phase 2: iOS — `AudioClip` にステータス＋transcript/訳フィールドを追加（optional/default でマイグレーション安全）
  - [x] Phase 3: iOS — `TranscriptionTranslationService` + Remote 実装（写真OCRサービスの音声版）
  - [x] Phase 4: iOS — `AudioDetailView` に手動「文字起こし」ボタンと状態分岐UIを追加
  - [x] Phase 5: バックエンド管理画面に文字起こしログ（一覧・音声試聴・コスト・削除）を追加
  - [ ] Phase 6: 検証（実Gemini疎通・状態遷移・specs 更新）

- [ ] lazy のAI生成読み上げがおかしい。生成プロンプトを検証