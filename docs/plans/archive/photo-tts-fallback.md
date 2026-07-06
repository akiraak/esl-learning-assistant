# 写真コンテンツ詳細の音声再生ボタン修正（サーバTTS失敗→端末TTSフォールバック）

## 目的・背景

写真コンテンツ詳細（`PhotoDetailView`）のスピーカーボタンを押すと、スピナーが一瞬出た後
無音でスピーカーアイコンに戻り、音が鳴らない（TODO: 「コンテンツの音声再生ボタンが効かない」）。

### 原因調査の結果（2026-07-05）

2 層の原因が判明した。

1. **環境・課金（根本原因）**: Gemini の TTS プレビューモデル
   （`gemini-2.5-flash-preview-tts` / `pro`）が `HTTP 429: Your prepayment credits are depleted`
   で失敗する。テキスト系モデル（word-info など）は正常に応答するため OCR 翻訳は通り、
   写真は「翻訳完了・再生だけ失敗」という症状になる。ローカルサーバ経由で再現確認済み。
   （コードでは直せない。課金の解消が必要）
2. **コードの不具合（無音の握りつぶし）**: `GeminiSpeechService.speak` が 401 以外のエラーを
   握りつぶして無音終了する（`GeminiSpeechService.swift:31-33`）。`WordDetailView` の TTS ボタンは
   `error.localizedDescription` を表示するのに、写真側だけ無反応に見える。

## 対応方針

ユーザー選択：**サーバTTS失敗時は端末内蔵TTS（SpeechService）へ自動フォールバック＋控えめな告知**。
課金や回線に依存せず常に音が出るようにし、失敗理由は BackendAPI の os.Logger で追える状態を維持する。

- 401/429/500・通信失敗いずれのサーバTTS失敗でも端末TTSへフォールバックする（無音終了しない）。
- フォールバック時は控えめなキャプション（数秒で自動消滅）で「端末音声で再生中」を告知する。
- モーダルアラート（`Speech Failed`）は廃止する（`GeminiSpeechService` は `PhotoDetailView` 専用）。

## 影響範囲

- `ios/.../Services/GeminiSpeechService.swift` — `speak` に失敗コールバック追加、`errorMessage` 廃止。
- `ios/.../Views/PhotoDetailView.swift` — フォールバック処理・控えめ告知UI追加、アラート廃止。
- 他への影響なし（`GeminiSpeechService` の利用は `PhotoDetailView` のみ）。

## テスト方針

- ローカルサーバ（Gemini TTS が 429 の状態）に接続し、写真詳細でスピーカー押下 →
  端末音声で読み上げられ、控えめ告知が数秒表示されることを実機/シミュレータで確認。
- `xcodebuild` でコンパイルが通ることを確認。
- TTS Model=local のときは従来どおり端末TTSで即読み上げ（回帰なし）。
