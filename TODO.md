# TODO

- [ ] TTSリキー移行（ttsPlainTextRekeyV1）が全端末に行き渡ったら移行コードを削除する
  - `MarkdownPlainText.legacyPlainText` と `TTSCacheRekeyMigration`（ContentView の起動フック含む）を削除
  - サーバ側 `POST /api/tts/rekey`・`rekeyTtsAudio` も端末が全て移行済みなら不要
- [ ] 熟語（２単語以上）を単語に入れる仕様を詰める
- [ ] レッスンをカレンダーに置き換える
  - クラスにはレッスンの日付が関連づけられる
  - 既存のレッスンはクラスカレンダーの日付に紐づく
  - クラスに同日のレッスンはない
  - レッスンの選択や作成はカレンダーのインターフェースから行う
- [ ] Audio再生にループ機能
