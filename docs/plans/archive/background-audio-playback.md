# 画面ロック・バックグラウンドでも音声再生を継続する

## 目的・背景

TTS 音声や取り込み音声（AudioClip）の再生中に、端末の画面を消す（サイドボタンでロック）
またはホーム画面に戻ると再生が止まってしまう。聞き流し用途（TODO の「Audio再生にループ機能」
とも関連）では、画面を閉じても鳴り続けてほしい。

原因は `UIBackgroundModes` に `audio` が設定されていないこと。iOS ではこれが無いと、
AVAudioSession を `.playback` にしていてもバックグラウンド移行（ロック含む）で音声が停止する。

現状の関連実装:

- `TTSPlaybackService` / `SpeechService` は再生時に `.playback` カテゴリ + `setActive(true)` を
  設定済み（`ios/ESLLearningAssistant/Sources/Services/TTSPlaybackService.swift:57-59` ほか）
- `ScreenWakeLock`（`isIdleTimerDisabled`）で再生中の自動ロックを防いでいるが、これは
  「自動ロックで音が切れる」ことへの回避策であり、手動ロック・ホーム移動では止まる

なお、アプリ内で詳細画面を閉じたときの `onDisappear { stop() }` は意図的な設計
（Audio 系は詳細 push で継続するよう親階層でプレイヤー保持済み）のため、本タスクでは変更しない。

## 対応方針

1. `ios/project.yml` の `targets.ESLLearningAssistant.info.properties` に
   `UIBackgroundModes: [audio]` を追加する
2. `xcodegen generate` で `Info.plist` / `pbxproj` を再生成する（pbxproj は生成物・手編集禁止）
3. コード変更は不要（セッション設定は既存のままで BG 再生が有効になる）

`ScreenWakeLock` は BG 再生対応後は「音切れ防止」としては不要になるが、
「画面を見ながら聞いている間は画面を消さない」という副次的な UX があるため今回は残す。

## 影響範囲

- `ios/project.yml`（Info.plist 生成設定のみ）
- 全ての音声再生（TTSPlaybackService / SpeechService / SoundEffectService）が
  ロック中・バックグラウンドで継続可能になる
- ロック画面の再生コントロール（MPNowPlayingInfoCenter / MPRemoteCommandCenter）は
  今回スコープ外（必要なら別タスク）

## テスト方針

- `xcodegen generate` 後にビルドとユニットテストが通ることを確認する
- ビルド生成物の `Info.plist` に `UIBackgroundModes: audio` が含まれることを確認する
- 実機で「再生 → サイドボタンでロック → 音が継続」を最終確認する（手動）
