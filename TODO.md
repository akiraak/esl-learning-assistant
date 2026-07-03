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
- [ ] 管理画面にAI料金表の定期更新を促す表示を入れる（単価は値下げされることがあるため、pricing.tsの単価表の最終更新日を記録し、一定期間経過したら管理画面に更新リマインドを表示する） [plan](docs/plans/pricing-update-reminder.md)
  - [ ] Step 1: pricing.ts — PRICING_LAST_UPDATED・鮮度判定ヘルパー・価格ページURL定数を追加
  - [ ] Step 2: admin.ts — 共通ヘッダに最終更新日表示と期限超過警告バナーを追加
  - [ ] Step 3: 動作確認（4ページ表示・過去日で警告バナー確認）
- [ ] 管理画面の表示をカッコ良く。デザイン例をいくつか作成して検証する