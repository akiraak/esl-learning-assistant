# TODO

- [ ] backend 公開デプロイ対応（g3plus + Docker + esl.chobi.me） [plan](docs/plans/public-deploy-api-secret.md)
  - [ ] `/api/*` に `X-API-Secret` ヘッダ認証を追加（backend コード変更）
  - [ ] iOS アプリから `/api/*` 呼び出し時に `X-API-Secret` ヘッダを送る（本番 URL 切替とセット）
  - デプロイ設定（Dockerfile / docker-compose / .env）は g3plus-ops リポジトリ側で管理

- [ ] ESLアプリ実装 [spec](docs/specs/app-spec.md)
  - [ ] Phase 3: 問題作成
  - [ ] シミュレータ/実機のGUI操作で撮影→OCR・翻訳フルフロー（クラス/レッスン作成→撮影→
        結果表示→失敗時の再試行）を動作確認する（ANTHROPIC_API_KEYは設定済みで、backend側の
        `/api/ocr-translate`実キー呼び出しはcurlで複数回成功確認済み。iOS側のGUI操作は
        シミュレータ/実機操作権限が無いこのセッションでは未確認）
  - [ ] Lessonページの Add photo を Contentの中に置く

- [ ] 管理画面のログ時間をシアトルのタイムゾーンにする
- [ ] クラス名・レッスン名編集の保存も明示的に `modelContext.save()` する（メモ機能の検証で、
      autosave任せだと保存直後にアプリを強制終了された場合に変更が失われることを確認済み。
      `LessonEditView` / `ClassEditView` / 各Add系ビューも同じパターンの可能性がある）

## デバックメニュー(On Setting)
  - 単語のAI生成物を全て削除