# Docs の文字起こし英語に読み上げ機能を追加（Photo と同様）

## 目的・背景

- `PhotoDetailView` の OCR 英文には読み上げ機能（サーバTTS生成→キャッシュ→再生、失敗時は端末内蔵TTSフォールバック、下部に `TTSPlayerBar` 操作パネル）があるが、
  `DocumentDetailView`（PDF/DOCX の抽出英文 `document.extractedText`）には無い。
- TODO: 「Photo と同様に Docs の文字起こし英語にも読み上げ機能を入れる」
- 読み上げスタックは既に共用部品化済みで、複数画面で実績あり:
  - `TTSButton`（生成→`TTSAudioStore` キャッシュ→再生。Photo / Word 詳細で使用）
  - `TTSPlaybackService` + `TTSPlayerBar`（一時停止・シーク・速度変更。Photo / Word / Audio 詳細で使用。`Form` 内でも動作実績あり = `AudioDetailView`）
  - `SpeechService`（端末内蔵TTS。サーバTTS失敗時のフォールバック）
- バックエンド `/api/tts` は最大 20,000 文字（1,500 文字ごとのチャンク合成）まで対応済み。
  超過時は 400 → Photo と同じく端末TTSフォールバックで救済される。

## 対応方針

単一 Phase。`DocumentDetailView` に `PhotoDetailView` と同じ配線を追加する。

1. **Markdown→プレーンテキスト変換の共通化**
   - `PhotoDetailView` 専用だった `plainText(_:)`（Markdown 記号を読み上げさせないための変換）を
     共通ヘルパー `Sources/Support/MarkdownPlainText.swift` に抽出する
   - `PhotoDetailView` は共通ヘルパー呼び出しに置き換える（挙動不変）
   - XcodeGen 管理のため、ファイル追加後 `xcodegen generate` を実行
2. **DocumentDetailView への読み上げ追加**（`PhotoDetailView` 47-74 / 103-132 行のミラー）
   - `@StateObject` で `SpeechService` / `TTSPlaybackService` を追加、`@State isUsingFallbackVoice` を追加
   - `completedExtract` の「Extracted Text (English)」ヘッダーを `HStack` 化し、末尾に
     `TTSButton(text: plainText(extractedText), playback:, errorMessage: .constant(nil), onGenerateFailure: フォールバック)` を追加
   - フォールバック時の控えめ告知ラベル（数秒で自動消滅）を追加
   - `Form` に `.safeAreaInset(edge: .bottom)` で `TTSPlayerBar`（`isActive` 時のみ）を追加
   - `.onDisappear` で `speechService.stop()` + `ttsPlayback.stop()`（画面離脱時に発話継続させない）

## 影響範囲

- 新規: `ios/ESLLearningAssistant/Sources/Support/MarkdownPlainText.swift`
- 変更: `ios/ESLLearningAssistant/Sources/Views/DocumentDetailView.swift`
- 変更（共通化のみ・挙動不変）: `ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`
- backend / SwiftData モデル / TTSAudioStore キャッシュキーの変更なし

## テスト方針

- `xcodebuild build` でコンパイル確認（Photo 側のリグレッション含む）
- シミュレータで手動確認: 文書詳細（抽出完了状態）でスピーカーボタン表示 → タップで生成→再生、
  `TTSPlayerBar` の出現、画面離脱で停止。Photo 詳細の読み上げが従来どおり動くこと
