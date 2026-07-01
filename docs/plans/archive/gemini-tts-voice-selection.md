# Gemini TTS版の音声読み上げ（声のタイプ選択つき）

## 目的・背景

[archive/tts-ocr-text-playback.md](archive/tts-ocr-text-playback.md) で `PhotoDetailView` に
端末内蔵TTS（`AVSpeechSynthesizer`、`Sources/Services/SpeechService.swift`）による
OCR結果（英語）読み上げを実装済み。

今回はより自然な音声のため、Gemini TTSをバックエンド経由で呼び出すバージョンを追加する。
声のタイプは `~/Projects/claude-code-manager/ai-monitor/` で定義済みの2キャラクター
（`voice-persona.json` / `src/persona.ts` / `src/tts.ts`）を流用する。

| キー | 名前 | Gemini prebuilt voice | スタイル |
|---|---|---|---|
| `chobi` | ちょビ | `Leda` | 終始にこにこしているような、柔らかく楽しげなトーンで読み上げてください |
| `naruko` | なるこ | `Aoede` | 元気で明るい声で、好奇心いっぱいに読み上げてください |

既存の端末内蔵TTSは残し、設定画面で「音声エンジン: 端末内蔵 / Gemini」を切り替えられるようにする
（Gemini選択時のみ「声のタイプ: ちょビ / なるこ」を選択可能）。

`backend/src/index.ts`（Express, Node v24でfetch内蔵・追加パッケージ不要）に
`POST /api/tts` を新設し、既存の `/api/ocr-translate` と同様の
バリデーション→処理→ログ→レスポンスの構造を踏襲する。

DB永続化・コスト計算（`db.ts`/`pricing.ts`）は今回は行わない。Gemini TTSの課金体系が
Claude APIと異なり`pricing.ts`の拡張が必要になるため、まずは`logger.ts`経由の
テキストログ（開始・成功・失敗・レイテンシ）のみとし、コスト集計が必要になったら別途対応する。

## 対応方針

### Phase 1: バックエンド（Gemini TTS API）

- `backend/.env.example` に `GEMINI_API_KEY` / `GEMINI_TTS_MODEL`
  （既定 `gemini-2.5-flash-preview-tts`）を追記
- `backend/src/config.ts` に `geminiApiKey` / `geminiTtsModel` を追加
- `backend/src/tts.ts` を新設
  - `VOICE_PRESETS`: `chobi`/`naruko` → `{ voiceName, style }`（claude-code-managerの値を移植）
  - `synthesizeSpeech(text, voiceKey)`: Gemini `generateContent` をfetchで直叩きし、
    返ってきたPCM(s16le/24kHz/mono)をWAVヘッダ付きBufferにラップして返す
    （`ai-monitor/src/tts.ts`の`pcmToWav`と同等ロジックを移植）
- `backend/src/index.ts` に `POST /api/tts` を追加
  - body: `{ text: string, voice: "chobi" | "naruko" }`
  - バリデーション: text必須（空文字/長すぎ拒否、上限2000字程度）、voiceは2値のみ許可
  - 成功時: `Content-Type: audio/wav` でバイナリ音声を返す
  - 失敗時: `500 { error }`、`logger`で開始・成功・失敗をログ

### Phase 2: iOS（設定画面・Gemini音声再生）

- `Sources/Support/AppSettingsKeys.swift` に追加
  - `ttsEngine`（既定 `"local"`、`"gemini"`）
  - `ttsVoice`（既定 `"chobi"`、`"naruko"`）
- `Sources/Views/SettingsView.swift` に「音声読み上げ」Sectionを追加
  - Picker「音声エンジン」: 端末内蔵 / Gemini
  - Picker「声のタイプ」: ちょビ / なるこ（Gemini選択時のみ有効）
- `Sources/Services/GeminiSpeechService.swift` を新設
  - `RemoteOCRTranslationService`と同様、`AppSettingsKeys.backendBaseURL`から
    URLを組み立てて`POST api/tts`をJSONで呼び出し、返ってきたWAV Dataを
    `AVAudioPlayer`で再生
  - `@Published isSpeaking` / `@Published isLoading`（生成中のスピナー表示用）、`stop()`
- `Sources/Views/PhotoDetailView.swift` の `speechButton` を、
  `ttsEngine`設定に応じて`SpeechService`（端末内蔵）と`GeminiSpeechService`（Gemini）の
  どちらを使うか分岐するよう修正。ボタンは1つのまま、生成中はProgressView、
  再生中はstopアイコンを表示。画面遷移時は両方に`stop()`を呼ぶ

## 影響範囲

- 新規: `backend/src/tts.ts`, `ios/.../Sources/Services/GeminiSpeechService.swift`
- 変更: `backend/.env.example`, `backend/src/config.ts`, `backend/src/index.ts`,
  `ios/.../Sources/Support/AppSettingsKeys.swift`, `ios/.../Sources/Views/SettingsView.swift`,
  `ios/.../Sources/Views/PhotoDetailView.swift`, Xcodeプロジェクトファイル（新規Swiftファイル登録）
- SwiftData モデルの変更なし、DBスキーマの変更なし

## テスト方針

- バックエンド: `GEMINI_API_KEY`設定後、`curl`で`/api/tts`にchobi/narukoそれぞれ投げ、
  200 & audio/wavが返り実際に再生できることを確認（キー設定はユーザー側で実施）
- iOS: `xcodebuild`でのシミュレータ向けビルド成功を確認
- 実機/シミュレータでのGUI操作・実際の音声再生確認はこのセッションでは行えないため、
  ユーザー側での確認を依頼する
