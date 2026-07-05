# TODO

- [ ] 写真の扱いを検討する [plan](docs/plans/photo-handling-review.md)
  - [ ] レッスンのコンテンツとして
  - [ ] レッスンのメモとして
  - [ ] レッスンに紐付かない写真の可能性を考える
- [ ] 複数ユーザーで使う場合の実装を検討する
- [ ] 音声データをアップする
- [ ] 作文機能。添削も入れる [plan](docs/plans/writing-composition-feedback.md)
  - [ ] Phase 0: 設計確定（3軸の確定・specs反映・タスク切り出し）
  - [ ] Phase 1: バックエンド（/api/writing-feedback・config・db/adminログ）
  - [ ] Phase 2: iOS データモデル＋通信（Composition・RemoteWritingFeedbackService）
  - [ ] Phase 3: iOS UI（一覧・エディタ・添削結果表示）
  - [ ] Phase 4: 仕上げ（空状態/エラー処理・仕様書更新）