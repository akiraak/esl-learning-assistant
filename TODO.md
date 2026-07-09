# TODO

- [ ] TTS用プレーンテキスト変換で見出しと直後の段落が区切りなし連結される問題を直す
  - `MarkdownPlainText`（旧 PhotoDetailView の plainText）が `AttributedString(markdown:)` でブロック境界の改行を落とし、例: `"The Sun and the WindThe north wind..."` のまま TTS に渡る（Photo/Docs 共通の既存問題）
  - 変換結果が TTS キャッシュキー（sha256("model|text")、端末 `TTSAudioStore`・サーバ `tts_audio` 両方）なので、修正すると既存の全文読み上げキャッシュが無効化され再合成課金が走る。キャッシュのパージ/移行方針とセットで対応する
- [ ] 熟語（２単語以上）を単語に入れる仕様を詰める
- [ ] レッスンをカレンダーに置き換える
  - クラスにはレッスンの日付が関連づけられる
  - 既存のレッスンはクラスカレンダーの日付に紐づく
  - クラスに同日のレッスンはない
  - レッスンの選択や作成はカレンダーのインターフェースから行う
- [ ] Audio再生にループ機能
