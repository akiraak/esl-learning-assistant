# iOS の X-API-Secret ヘッダ対応 + 本番 URL 切替

## 目的・背景

backend の `/api/*` に `X-API-Secret` ヘッダ認証が入った（[plan](public-deploy-api-secret.md)、2026-07-01 デプロイ済み）。
iOS アプリ側もヘッダを送らないと全 API が 401 になるため、以下を対応する。

- `/api/*` を呼ぶ全リクエストに `X-API-Secret` ヘッダを付与する
- secret は Settings 画面で入力・変更できるようにする（コードにハードコードしない）
- デフォルトの接続先を本番 `https://esl.chobi.me` に切り替える（ローカル開発時は Settings から戻せる）
- 401 のとき「Settings で API Secret を確認」と分かるメッセージを表示する

## 対応方針

### Step 1: 設定まわり

- `AppSettingsKeys` に `apiSecret` キーと `defaultAPISecret` を追加
  （`backendBaseURL` と同じ UserDefaults + Info.plist（`BackendAPISecret`）パターン。
  Info.plist 値はビルド設定 `BACKEND_API_SECRET` 経由で埋め込み、既定は空文字）
- `defaultBackendBaseURL` のフォールバックを `http://localhost:8801` → `https://esl.chobi.me`
- `project.yml`: `BACKEND_BASE_URL` の既定を `https://esl.chobi.me` に変更、
  `BACKEND_API_SECRET`（既定空）と Info.plist の `BackendAPISecret` を追加 → `xcodegen generate`
- `run-ios-device.sh`: `--local`（デフォルト）/ `--prod` で接続先を切り替える。
  `--local` は Mac IP 自動検出 + `backend/.env` の `API_SECRET` を自動注入、
  `--prod` は `https://esl.chobi.me` + `.env.prod`（gitignore対象、`.env.prod.example`
  参照）の `API_SECRET` を埋め込む。`BACKEND_API_SECRET` 環境変数で上書きも可能
- `SettingsView`: Server URL 欄の下に API Secret 入力欄を追加。footer 文言も本番前提に更新

### Step 2: リクエスト共通化 + 401 エラー整備

- 新規 `Services/BackendAPI.swift`:
  - `BackendAPI.postRequest(path:body:)` — base URL / secret を Settings から読み、
    JSON POST の `URLRequest` を生成（3 サービスの重複を解消）
  - `BackendAPI.validate(response:)` — 200 以外を `BackendAPIError` に変換（401 は `.unauthorized`）
  - `BackendAPIError`: `invalidBaseURL` / `unauthorized` / `serverError(statusCode:)`。
    `errorDescription` で 401 に「Check the API Secret in Settings」を含める
- `RemoteOCRTranslationService` / `RemoteWordInfoService` / `GeminiSpeechService` を共通化に乗せ替え
  （`WordInfoServiceError` は `BackendAPIError` に置き換え、テストも追随）

### Step 3: 401 エラーのユーザー表示

- `Photo` に `processingErrorMessage: String?` を追加（optional 追加のみ＝軽量マイグレーション維持）。
  失敗時にメッセージを保存、成功時にクリア。`PhotoDetailView` の failed 表示に併記
- `Word` に `aiInfoErrorMessage: String?` を追加。`WordAIInfoGenerator` の catch で保存。
  `WordDetailView` の failed セクションに併記
- `GeminiSpeechService` に `@Published errorMessage` を追加し、`PhotoDetailView` で alert 表示

### Step 4: 動作確認

- `backend/.env` に `API_SECRET` を追加（ローカル backend は未設定だと起動しない。値は本番と別でよい）
- xcodebuild でビルド + 既存ユニットテストが通ること
- 本番 `https://esl.chobi.me` に対する OCR翻訳 / 単語情報 / TTS のフルフロー確認
  （Cloudflare 設定完了後。シミュレータ GUI 操作が必要なら手動確認）

## 影響範囲

- iOS アプリ全体の backend 接続（デフォルトが本番になる。ローカル開発時は Settings で
  `http://localhost:8801` に切り替え + API Secret にローカルの値を入力）
- SwiftData スキーマ（Photo / Word への optional プロパティ追加のみ）
- ローカル backend 起動に `backend/.env` の `API_SECRET` が必須

## テスト方針

- 既存ユニットテスト（WordAIInfoTests 等）が通ること
- 401 時に Photo / Word にエラーメッセージが保存されることをユニットテストで確認（Mock で 401 を返す）
- 実サーバ疎通は curl（`/health`、ヘッダなし 401、正ヘッダ 200）で確認
