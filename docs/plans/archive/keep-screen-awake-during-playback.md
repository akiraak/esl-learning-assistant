# 音声再生中の自動スリープ抑止

## 目的・背景

音声再生中に iPhone が自動ロック（スリープ）するとアプリがサスペンドされ、再生が途切れてしまう。
再生中は画面を消させない（自動ロックを止める）ことで、再生が止まらないようにする。

- 対応方針は「再生中は画面を消させない」を採用（バックグラウンド再生ではなく前面維持）。
- `UIApplication.shared.isIdleTimerDisabled = true` を再生中だけ有効にする。

## 対応方針

`isIdleTimerDisabled` はアプリ全体で共有される 1 つのフラグのため、複数の再生サービスが
個別に true/false を書き込むと、片方の停止でもう片方の再生中に自動ロックが復活してしまう。
これを避けるため、所有者（サービスインスタンス）ベースでロックを集約する小さなヘルパーを追加する。

- `Support/ScreenWakeLock.swift` を新規追加
  - `setActive(_ active: Bool, owner: AnyObject)` を提供
  - 要求中の owner を `Set<ObjectIdentifier>` で保持し、1 つでも要求があれば `isIdleTimerDisabled = true`
  - すべて解放されたら `false` に戻す（冪等・リークしない）
- `TTSPlaybackService`: 再生状態が変わるたびに `ScreenWakeLock.setActive(isPlaying, owner: self)` を呼ぶ
  - start(autoPlay) / resume / pause / stop / 再生終了(delegate) の各所
- `SpeechService`: `speak` で true、`stop` / didFinish / didCancel で false

## 影響範囲

- 新規: `ios/ESLLearningAssistant/Sources/Support/ScreenWakeLock.swift`
- 変更: `TTSPlaybackService.swift`, `SpeechService.swift`
- XcodeGen 管理のため、ファイル追加後に `xcodegen generate` は不要（sources はディレクトリ指定）だが、
  ビルドで拾われることを確認する。

## テスト方針

- ビルドが通ること。
- 実機で長い音声を再生し、自動ロック時間を超えても画面が消えず再生が継続すること。
- 再生停止後は自動ロックが復活すること（`isIdleTimerDisabled` が false に戻る）。
