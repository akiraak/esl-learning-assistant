# TODO


- [ ] 問題作成
- [ ] 管理画面のログ時間をシアトルのタイムゾーンにする
- [ ] クラス名・レッスン名編集の保存も明示的に `modelContext.save()` する（メモ機能の検証で、
      autosave任せだと保存直後にアプリを強制終了された場合に変更が失われることを確認済み。
      `LessonEditView` / `ClassEditView` / 各Add系ビューも同じパターンの可能性がある）
- [ ] TTSデータをサーバで保存する機能を入れる [plan](docs/plans/tts-server-storage.md)
  - 単語詳細の Meanings, Examples の英文をTTSで生成してアプリで聞けるようにする
  - [ ] Phase 1: backend — `tts_audio` テーブル＋`data/tts/` 保存、`/api/tts` キャッシュ対応
  - [ ] Phase 2: 管理画面 — TTS一覧（試聴・削除）
  - [ ] Phase 3: iOS — WordDetailView の Meanings / Examples に生成→再生ボタン（サーバTTS＋端末ローカル保存）

## デバックメニュー(On Setting)
  - 単語のAI生成物を全て削除