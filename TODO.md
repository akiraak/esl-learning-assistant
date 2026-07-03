# TODO


- [ ] 問題作成
- [ ] アプリ側音声生成に一時停止や早送りなど一般的な再生プレイヤーの機能を入れる
  - 表示されている画面を見ながら音声を聞けるように操作パネルは邪魔にならない場所におく
  - 読み上げ
- [ ] 管理画面TTS一覧に音声の長さと生成料金を表示 [plan](docs/plans/tts-admin-duration-cost.md)
  - [ ] Step 1: db.ts — tts_audio に input_tokens / output_tokens / cost_usd 追加＋後方互換マイグレーション
  - [ ] Step 2: tts.ts — Gemini usageMetadata を取得しチャンク合算で返す
  - [ ] Step 3: pricing.ts — Gemini TTS 単価を追加（公式価格を確認して反映）
  - [ ] Step 4: index.ts — /api/tts で料金計算して保存・ログ出力
  - [ ] Step 5: admin.ts — TTS一覧に「長さ」「料金」列と料金合計を表示
- [ ] アプリSettingからSpeechEngineを削除。TTS Modelだけで選択できるように。Gemini 2.5 TTS などモデル名の詳細を表示する
- [ ] 管理画面の表示をカッコ良く。デザイン例をいくつか作成して検証する