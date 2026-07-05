# Audio 一覧の再生ボタン削除・詳細の自動再生停止

## 目的・背景

Audio 一覧（Audioタブ・レッスン画面）の各行に再生/停止ボタンが並んでおり、
行タップで詳細へ遷移すると同時に自動再生も始まる。UX を整理したい。

- 一覧の各行から再生/停止ボタンを削除する
- 詳細へ遷移したあと自動で再生するのをやめる

## 対応方針

1. **一覧の再生ボタン削除**
   - `AudioClipRow`（AudioView.swift）から再生/停止ボタンと `isPlaying`/`onPlayToggle` を除去し、
     タイトル＋レッスン名だけの表示にする。
   - 呼び出し側（AudioView・LessonsView）の `AudioClipRow(...)` を新シグネチャに合わせる。

2. **自動再生の停止**
   - 行タップ時の `togglePlay(clip)` / `toggleAudio(clip)` 呼び出しを削除し、遷移のみ行う。
   - 詳細（AudioDetailView）で再生できる手段を残すため、`TTSPlaybackService` に
     「再生せずにロードだけする」`prepare(url:)` を追加し、`onAppear` で呼ぶ。
     → `TTSPlayerBar` が一時停止状態で表示され、ユーザーが再生ボタンを押せる。
   - 一覧側で不要になった `togglePlay`/`toggleAudio`/`isPlaying` ヘルパを整理する。

## 影響範囲

- ios/.../Views/AudioView.swift（AudioClipRow・行タップ・ヘルパ）
- ios/.../Views/LessonsView.swift（audioSection・ヘルパ）
- ios/.../Views/AudioDetailView.swift（onAppear で prepare）
- ios/.../Services/TTSPlaybackService.swift（prepare 追加）

## テスト方針

- 既存の TTSPlaybackServiceTests に prepare の挙動（isActive=true / isPlaying=false）を追加。
- ビルドが通ること、行タップで詳細に遷移し自動再生しないことを確認。
