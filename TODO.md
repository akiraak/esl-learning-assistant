# TODO


- [ ] 問題作成
- [ ] 管理画面のログ時間をシアトルのタイムゾーンにする
- [ ] クラス名・レッスン名編集の保存も明示的に `modelContext.save()` する（メモ機能の検証で、
      autosave任せだと保存直後にアプリを強制終了された場合に変更が失われることを確認済み。
      `LessonEditView` / `ClassEditView` / 各Add系ビューも同じパターンの可能性がある）
- [ ] 単語データをサーバに保存 [plan](docs/plans/word-info-server-storage.md)
  - アプリから単語の情報取得のメッセージが来たらとき存在していればそれを返し、なければAIで生成する。再生性のメッセージが来た時は作成しなおす
  - サーバ管理画面に単語一覧を作成。削除や再生性を可能にする
  - [ ] Phase 1: backend — `words` テーブル新設、`/api/word-info` のキャッシュ返却・`regenerate` 対応
  - [ ] Phase 2: 管理画面 — 単語一覧・詳細ページ（削除・再生成ボタン）
  - [ ] Phase 3: iOS — 「AI情報を再生成」で `regenerate: true` を送る
- [ ] TTSデータをサーバで保存する機能を入れる [plan](docs/plans/tts-server-storage.md)
  - 単語詳細の Meanings, Examples の英文をTTSで生成してアプリで聞けるようにする
  - [ ] Phase 1: backend — `tts_audio` テーブル＋`data/tts/` 保存、`/api/tts` キャッシュ対応
  - [ ] Phase 2: 管理画面 — TTS一覧（試聴・削除）
  - [ ] Phase 3: iOS — WordDetailView の Meanings / Examples に生成→再生ボタン（サーバTTS＋端末ローカル保存）

## デバックメニュー(On Setting)
  - 単語のAI生成物を全て削除