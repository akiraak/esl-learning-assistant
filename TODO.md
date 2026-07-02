# TODO

- [ ] backend 公開デプロイ対応（g3plus + Docker + esl.chobi.me） [plan](docs/plans/public-deploy-api-secret.md)
  - [x] `/api/*` に `X-API-Secret` ヘッダ認証を追加（backend コード変更、2026-07-01 デプロイ済み。
        本番 `https://esl.chobi.me/` も稼働確認済み: /health 200、ヘッダなし /api/* 401）
  - [ ] iOS アプリの `X-API-Secret` ヘッダ対応 + 本番 URL 切替 [plan](docs/plans/ios-api-secret-header.md)
    - [x] `AppSettingsKeys` に `apiSecret` キーを追加（`backendBaseURL` と同じ
          UserDefaults + Info.plist デフォルト値のパターン。secret はコードにハードコードしない）
    - [x] `SettingsView` の Server URL 欄の下に API Secret 入力欄を追加
    - [x] `/api/*` を呼ぶ 3 サービスの URLRequest に `X-API-Secret` ヘッダを付与
          （`Services/BackendAPI.swift` にリクエスト生成・レスポンス検証を共通化）
    - [x] 401（secret 不一致・未設定）のエラーを「Check the API Secret in Settings」と分かる
          メッセージでユーザーに表示する（Photo.processingErrorMessage / Word.aiInfoErrorMessage
          に保存して表示、TTS は alert）
    - [x] 本番 URL 切替: デフォルトの base URL を `https://esl.chobi.me` にする
          （`AppSettingsKeys.defaultBackendBaseURL` のフォールバックと project.yml の
          `BACKEND_BASE_URL`。ローカル開発時は Settings 画面から `http://localhost:8801` に戻せる。
          実機ローカル開発は run-ios-device.sh が Mac IP + backend/.env の API_SECRET を注入）
    - [ ] 本番サーバに対して OCR翻訳 / 単語情報 / TTS のフルフローを動作確認
          （本番 secret を Settings 画面に入力してアプリ GUI で確認。secret の取得と
          GUI 操作が必要なため手動。curl では本番のヘッダなし 401 / /health 200 は確認済み。
          ※ 2026-07-02 の失敗は .env.prod / Settings にローカル用 secret を入れていたのが原因。
          本番の値は Sx360 の g3plus-ops/esl-learning-assistant/.env からコピーすること）
    - [x] 接続問題の切り分け支援 [plan](docs/plans/backend-api-logging.md)
      - [x] BackendAPI に os.Logger のリクエスト/レスポンスログとサーバエラーメッセージの取り込み
      - [x] Settings に Test Connection ボタン（/health 疎通 + /api/ping で secret 一致確認）
      - [x] backend に GET /api/ping を追加（ローカルで 401/200 確認済み。
            本番反映は次回 g3plus-ops デプロイ時。未反映でも 404 判定で Test Connection は動く）
    - secret の値は Sx360 の `g3plus-ops/esl-learning-assistant/.env`（`API_SECRET=`）にある。
      ローカル開発時は `backend/.env` にも同じキー名で設定が必要（未設定だと backend が起動しない）
  - デプロイ設定（Dockerfile / docker-compose / .env）は g3plus-ops リポジトリ側で管理
    （運用手順: g3plus-ops の docs/workflows/esl-learning-assistant.md）

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