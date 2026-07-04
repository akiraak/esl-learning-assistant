# 管理画面で単語クイズの音声データを再生できるようにする

## 目的・背景

クイズ問題の audioText はサーバ側で AI プリ合成され `tts_audio`（キャッシュキー
sha256("flash|audioText")）に保存されるが、管理画面の単語クイズ詳細
（`/admin/quiz-questions/item`）では audioText がテキスト表示されるだけで、
実際にどんな音声が再生されるのか確認できない。プリ合成の成否・音質を
管理画面から耳で確認できるようにする。

## 対応方針

- `/admin/quiz-questions/item` の各問題行で、`audioText` がある場合に
  sha256("flash|audioText") で `tts_audio` を引く（`getTtsAudioByHash`）
  - ヒットしたら既存の音声配信エンドポイント `/admin/tts/:id/audio` を
    src にした `<audio controls preload="none">` を表示する（TTS一覧と同じ UI）
  - 未合成（プリ合成失敗など）の場合は「音声未合成」と表示する
- モデルは `ttsStore.ts` の `QUIZ_TTS_MODEL`（flash 固定）を参照し、
  ハッシュ計算のロジックはキー仕様（sha256("model|text")）と一致させる

## 影響範囲

- `backend/src/admin.ts` のみ（クイズ詳細ページの描画に音声列を追加）
- 新規エンドポイントなし（既存の `/admin/tts/:id/audio` を再利用）

## テスト方針

- `npm run build`（tsc）が通ることを確認する
- ローカルでサーバを起動し、既存データのあるクイズ詳細ページを curl して
  `<audio>` タグが合成済み audioText の行に出力されることを確認する
- ブラウザ再生は既存 TTS 一覧と同一機構のため、タグ出力の確認をもって代える
