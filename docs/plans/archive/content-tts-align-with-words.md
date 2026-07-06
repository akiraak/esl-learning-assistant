# コンテンツ（写真）の音声生成・再生を単語と同じ仕組みに揃える（調査）

## 目的・背景

写真コンテンツ詳細（`PhotoDetailView`）の音声生成・再生を、単語詳細（`WordDetailView`）の
仕組み（生成→端末ローカルにキャッシュ→URL再生＋プレイヤーバー）に統一したい。
現状は 2 系統が別実装になっており、キャッシュの有無・状態表現・失敗時挙動が食い違う。

## 現状の 2 実装の比較

### 単語（`WordDetailView` の `TTSButton`, 620-688 行）＝目標形

- ボタンは項目単位（見出し語 `:354` / 語義定義 `:382` / 例文 `:424`）。それぞれ独立生成。
- 状態は `TTSAudioStore.localURL(text:model:)` の**ファイル存在**から導出（3状態）:
  - 未生成 → `waveform.badge.plus`（タップで生成）
  - 生成済・停止中 → `speaker.wave.2.fill`（`playback.play(url:)` で再生）
  - 生成済・この音源が再生中 → `stop.fill`（`playback.stop()`）
  - 生成中 → `ProgressView`
- モデルは `serverModel`（`ttsModel=="local"` のときは `fallbackServerTTSModel="flash"` に読み替え）。
  → On-Device 設定でも AI 音声生成はサーバ TTS を使う。
- 生成: `BackendAPI.post("api/tts", {text, model})` → `TTSAudioStore.save(data:text:model:)`。
- 再生: `TTSPlaybackService.play(url:)`。`ttsPlayback.isActive` の間だけ画面下部に
  `TTSPlayerBar` を出す（`.safeAreaInset(edge:.bottom)`, `WordDetailView.swift:139-143`）。
- 失敗: `ttsErrorMessage` にセット → `.alert("Audio Generation Failed")`（`:163-173`）。**フォールバック無し**。
- キャッシュ: `TTSAudioStore` = `ApplicationSupport/tts/<sha256("model|text")>.wav`。
  再訪・オフラインでも「生成済＝即再生」を維持。キーはサーバ側 `tts_audio.text_hash` と同一。
- 別途 `SpeechButton`（`:690-716`）が端末内蔵TTS（`SpeechService`）で即読み上げ（AIとは別ボタン）。
- `onDisappear` で `speechService.stop()` / `ttsPlayback.stop()`（`:159-162`）。

### 写真（`PhotoDetailView`、現状）

- 単一のスピーカーボタンで OCR 全文を読み上げ（`speechButton`, `:146-162`）。
- `ttsModel != "local"` → `GeminiSpeechService.speak` → POST → `playback.play(data:)`
  （**メモリ直再生・キャッシュ無し**）。失敗時は端末TTS（`SpeechService`）へフォールバックし
  "Server voice unavailable — using on-device voice" を数秒告知（前タスクで実装）。
- `ttsModel == "local"` → `SpeechService.speak`（端末内蔵TTS）。
- `TTSPlayerBar` は `ttsPlayback.isActive` の間だけ表示（単語と同じ safeAreaInset）。

## 差分（何を変えるか）

| 観点 | 写真（現状） | 単語（目標） |
|---|---|---|
| 音源取得 | `GeminiSpeechService.speak` | `BackendAPI.post("api/tts")` 直呼び |
| 保存 | しない（`play(data:)`） | `TTSAudioStore.save` にキャッシュ |
| 再生 | `playback.play(data:)` | `playback.play(url:)` |
| 状態 | isSpeaking/isLoading | `TTSAudioStore.localURL` の存在で3状態 |
| モデル | `ttsModel`(local時は端末TTS) | `serverModel`(local→flash) |
| 失敗時 | 端末TTSフォールバック＋告知 | `.alert` 表示、フォールバック無し |

## 決定事項（ユーザー確認済み）

1. **失敗時はフォールバックを残す**: サーバTTS生成失敗時は、前タスクどおり端末内蔵TTS
   （`SpeechService`）へフォールバックし "Server voice unavailable — using on-device voice" を
   数秒だけ控えめ告知する（単語の `.alert` 方式は写真では使わない）。
2. **AI 音声ボタンのみに集約**: 写真は AI 音声（`TTSButton`）1 つに集約。端末TTSの即読み専用
   ボタン（単語の `SpeechButton` 相当）は写真には置かない（フォールバック経由でのみ端末TTSを使う）。

## 対応方針（実装案・確定）

1. **共有コンポーネント化**: `WordDetailView` 内 `private struct TTSButton` を独立ファイル
   （例 `Views/TTSButton.swift`）へ切り出し、写真・単語の両方から使う。
   - `TTSButton` は自己完結（`text` / `playback` / `errorMessage` バインディング / `@AppStorage(ttsModel)`）で
     依存が閉じており、抽出は容易。`WordDetailView` 側は参照に置換するだけ。
2. **`TTSButton` に失敗フックを追加**: 生成失敗時の扱いを呼び出し側で差し替えられるよう、
   任意の `onGenerateFailure: (() -> Void)?`（既定 nil）を追加する。
   - `generate()` の `catch`: `onGenerateFailure` があればそれを呼ぶ、無ければ従来どおり
     `errorMessage`（→単語の `.alert`）をセット。→ 単語は挙動不変、写真だけフォールバックにできる。
3. **`PhotoDetailView` を `TTSButton` ベースに置換**:
   - OCR 完了セクションのスピーカーを
     `TTSButton(text: plainText(photo.ocrText), playback: ttsPlayback, errorMessage: .constant(nil), onGenerateFailure: { fallBackToOnDeviceVoice(text) })` に差し替え。
   - 生成成功時は `TTSAudioStore` にキャッシュされ、以降は `TTSPlayerBar` で再生/停止/シーク/速度変更。
   - フォールバック用に `speechService` / `isUsingFallbackVoice` / `fallBackToOnDeviceVoice` /
     控えめ告知UI は**維持**する。
   - `onDisappear` で `speechService.stop()` / `ttsPlayback.stop()`。
4. **不要物の削除**:
   - `GeminiSpeechService`（写真専用・他未使用）は用途が無くなるため削除する。
   - `PhotoDetailView` の旧 `speak()`（サーバ/ローカル分岐）は撤去。フォールバックは `TTSButton` の
     `onGenerateFailure` 経由に一本化。

## 補足（UX・互換の留意点）

- **2段階UX**: 単語方式は「1タップ目=生成（スピナー）→2タップ目=再生」。写真全文は生成に
  数秒〜十数秒かかるが、`TTSAudioStore` にキャッシュされるので 2 回目以降は即「再生」状態で開く。
- **キャッシュキー**: `sha256("model|全文プレーンテキスト")`。OCR 再翻訳で本文が変わると別キー＝再生成。
- **フォールバック時のボタン状態**: 生成失敗時は cache が無いのでボタンは「生成」表示のまま。
  端末TTS再生は `speechService` 側で進行し、告知キャプションで補足する。

## 影響範囲

- `ios/.../Views/WordDetailView.swift` — `TTSButton` を外部ファイル参照へ変更。
- `ios/.../Views/TTSButton.swift`（新規） — 共有コンポーネント。
- `ios/.../Views/PhotoDetailView.swift` — スピーカー実装差し替え・alert 追加・フォールバック/告知 撤去。
- `ios/.../Services/GeminiSpeechService.swift` — 削除候補。
- テスト: 既存 TTS 系テストへの影響確認（`TTSPlaybackServiceTests` / `TTSAudioStoreTests`）。

## テスト方針

- `xcodebuild` でビルド確認。
- ローカルサーバ（Gemini TTS が課金枯渇=429 の状態）では生成が失敗するため、`.alert` 表示 or
  フォールバック（決定次第）を確認。課金補充後は生成→キャッシュ→再生の一連を実機/シミュレータで確認。
- 単語側の TTS が回帰していないこと（抽出後も従来どおり生成・再生・停止できる）を確認。
