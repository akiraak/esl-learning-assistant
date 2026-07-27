# TODO

- [ ] アプリで音声ファイルの文字起こしをすると400エラーが起きる [plan](docs/plans/audio-transcribe-400.md)
  - 原因確定: 本番サーバー（esl.chobi.me）の `GEMINI_API_KEY` が無効。コード側のバグではない
  - [ ] Sx360 の `g3plus-ops/esl-learning-assistant/.env` の `GEMINI_API_KEY` を差し替えて `up -d`
  - [ ] 本番アプリで文字起こしが成功することを確認
  - [ ] 同じキーを使う本番 `/api/tts`（Gemini TTS）も復旧しているか確認
