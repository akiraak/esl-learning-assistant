# Audio 再生にループ機能

## 目的・背景

- TODO: 「Audio再生にループ機能」
- リスニング/シャドーイング練習では同じ音源を繰り返し聞くことが多い。
  現状は再生終了で `stop()` されプレイヤーが閉じるため、毎回開き直して再生し直す必要がある。
- 再生UIは `TTSPlaybackService`（状態源）＋ `TTSPlayerBar`（操作パネル）に集約されているので、
  そこにループトグルを1つ追加すれば全画面（Audio詳細・単語詳細・写真詳細・ドキュメント詳細など）で使えるようになる。

## 対応方針

1. `TTSPlaybackService` にループ状態を追加
   - `@Published private(set) var isLoopEnabled = false`
   - `func toggleLoop()` でフラグを反転し、ロード済みプレイヤーへ即時反映
   - 実装は `AVAudioPlayer.numberOfLoops`（ON = `-1` 無限ループ / OFF = `0`）。
     ギャップレスで OS 側がループしてくれるため、`audioPlayerDidFinishPlaying` は
     ループ中は呼ばれず、OFF に戻せば従来どおり終了時に `stop()` される。
   - `start(player:url:autoPlay:)` でも現在のフラグを新プレイヤーに適用する。
   - 再生速度 `rate` と同様、音源をまたいで設定を維持する（stop でリセットしない）。
2. `TTSPlayerBar` にループボタンを追加
   - 左側の速度メニュー横に `repeat` アイコンのトグルボタンを置く。
     ON のときは tint（アクセント色）、OFF のときは secondary で状態を示す。
   - `accessibilityLabel` は "Repeat On/Off" 相当を付ける。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Services/TTSPlaybackService.swift`
- `ios/ESLLearningAssistant/Sources/Views/TTSPlayerBar.swift`
- TTSPlayerBar を使う全画面（AudioDetailView / WordDetailView / PhotoDetailView /
  DocumentDetailView / AudioLibraryView）に共通で機能が乗るが、呼び出し側の変更は不要。

## テスト方針

- `xcodebuild` でビルドが通ることを確認する。
- シミュレータで AudioDetail を開き、ループ ON で再生 → 終端到達後も再生が続くこと、
  OFF に戻すと終端で停止（プレイヤーが閉じる）ことを確認する。
