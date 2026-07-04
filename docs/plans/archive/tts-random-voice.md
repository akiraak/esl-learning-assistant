# TTS キャラクターのランダム選択化と Setting のキャラ選択削除

## 目的・背景

現状、TTS のキャラクター（chobi / naruko）はアプリの Settings で固定選択している。
これを、生成時にサーバ側で 2 キャラからランダムに選択する方式に変更し、
アプリの Settings からキャラ選択 UI を削除する。

## 対応方針

音声キャラの決定をサーバ側に一元化する。

- **backend**
  - `POST /api/tts` のリクエストから `voice` を廃止（受け取っても無視）
  - キャッシュキーを `sha256("${voice}|${model}|${text}")` → `sha256("${model}|${text}")` に変更
    - 同一テキストは初回生成時にランダムで選ばれたキャラに固定され、以後はキャッシュが効く
  - キャッシュミス時に `VOICE_PRESETS` のキーからランダムに 1 キャラ選択して生成
  - DB (`tts_audio.voice`) には実際に使ったキャラを引き続き記録
- **iOS**
  - `SettingsView` から音声キャラの Picker を削除
  - `AppSettingsKeys.ttsVoice` / `defaultTTSVoice` を削除
  - `GeminiSpeechService.RequestBody` / `speak()` から `voice` を削除
  - `TTSAudioStore.key` を `sha256("model|text")` に変更（サーバと同一キー維持）
  - `PhotoDetailView` / `ReviewSessionView` / `WordDetailView` から `ttsVoice` の参照を削除

### キャッシュ移行について

ハッシュ形式が変わるため、既存のキャッシュ（サーバの WAV + DB 行、iOS ローカルの WAV）は
ヒットしなくなり、必要に応じて再生成される。個人開発用途のため移行処理は行わない
（旧ファイルは孤児として残るが実害なし）。

## 影響範囲

- backend: `src/index.ts` (`/api/tts`), `src/tts.ts`
- iOS: `SettingsView.swift`, `AppSettingsKeys.swift`, `GeminiSpeechService.swift`,
  `TTSAudioStore.swift`, `PhotoDetailView.swift`, `ReviewSessionView.swift`, `WordDetailView.swift`
- テスト: `TTSAudioStoreTests.swift`

## テスト方針

- backend: `npm run build`（型チェック）
- iOS: `TTSAudioStoreTests` をキー形式変更に合わせて更新し、ユニットテストを実行
- 手動確認: アプリから TTS 生成 → 2 キャラのいずれかで生成されること、
  同一テキスト再生成でキャッシュが効くこと
