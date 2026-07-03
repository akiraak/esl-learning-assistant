# アプリ側 生成音声プレイヤーに一時停止・早送り等の操作パネルを追加

## 目的・背景

- 現状、生成音声（サーバTTS）の再生は「再生 / 停止」のみ。一時停止・シーク・早送り／巻き戻しができない
- 特に PhotoDetailView の OCR 全文読み上げは長尺になるため、途中で止めて聞き直す操作が必須
- TODO: 「アプリ側音声生成に一時停止や早送りなど一般的な再生プレイヤーの機能を入れる」
  - 「表示されている画面を見ながら音声を聞けるように操作パネルは邪魔にならない場所におく」

## 現状

- `TTSPlaybackService`: `AVAudioPlayer` によるローカルWAVファイル再生。`playingURL` のみ公開。進捗・一時停止・シークなし
- `GeminiSpeechService`: PhotoDetailView 専用。`/api/tts` からWAVを取得しメモリから直接再生。独自に `AVAudioPlayer` を持つ（プレイヤー実装が重複）
- UI は各行末のインライン再生ボタンのみ（`TTSButton` / PhotoDetailView の `speechButton`）。パネル・スクラバーなし

## 対応方針

### Phase 1: TTSPlaybackService をフル機能プレイヤーに拡張

- `play(url:)` に加え `play(data:)`（PhotoDetail のメモリ再生用）を追加
- 公開状態を拡張: `currentURL`（ロード中の音源。旧 `playingURL`）、`isPlaying`、`isActive`（音源ロード有無）、`currentTime`、`duration`、`rate`
- 操作を追加: `pause()` / `resume()` / `togglePlayPause()` / `seek(to:)` / `skip(by:)` / `setRate(_:)`（`enableRate`）
- 再生中は 0.2s タイマーで `currentTime` を更新。停止・再生完了で無効化
- 再生完了時は従来どおり状態をリセット（パネルも自動で閉じる）

### Phase 2: 共通操作パネル `TTSPlayerBar` を新規作成

- 新規ファイル `Sources/Views/TTSPlayerBar.swift`
- 構成（コンパクト1〜2段）: 5秒巻き戻し / 再生・一時停止 / 5秒送り / シークバー（ドラッグでシーク）/ 経過・総時間 / 再生速度メニュー（0.5〜1.5×）/ 閉じる（停止）
- ホスト画面に `.safeAreaInset(edge: .bottom)` で表示。`isActive` のときだけ出現し、コンテンツを隠さず下部に挿入される（マテリアル背景で邪魔にならない見た目）
- XcodeGen 構成のため、ファイル追加後 `xcodegen generate` を実行

### Phase 3: WordDetailView へ組み込み

- `List` に `.safeAreaInset(edge: .bottom)` で `TTSPlayerBar` を追加
- `TTSButton` の再生中判定を `currentURL` + `isPlaying` ベースに更新（行ボタンの見た目・挙動は従来どおり再生/停止トグルを維持）

### Phase 4: PhotoDetailView へ組み込み（GeminiSpeechService の再生を共通化）

- `GeminiSpeechService` から内部 `AVAudioPlayer` を撤去し、取得したWAVデータを `TTSPlaybackService.play(data:)` に渡す（fetch専任化。`isLoading` / `errorMessage` は維持、`isSpeaking` は playback 側の状態に置き換え）
- PhotoDetailView に `TTSPlaybackService` を `@StateObject` で追加し、同じ `TTSPlayerBar` を表示

## 影響範囲

- 変更: `TTSPlaybackService.swift` / `GeminiSpeechService.swift` / `WordDetailView.swift` / `PhotoDetailView.swift`
- 新規: `TTSPlayerBar.swift`
- 対象外: `SpeechService`（端末内蔵TTS。シーク不可のため今回のパネル対象にしない）、backend、TTSAudioStore のキャッシュキー

## テスト方針

- `xcodebuild build` でコンパイル確認、既存ユニットテスト（TTSAudioStoreTests 等）の回帰確認
- シミュレータで手動確認: 単語詳細で生成音声を再生→パネル表示、一時停止/再開、±5秒、シークバー、速度変更、閉じる、画面離脱時の停止。写真詳細でも同様
