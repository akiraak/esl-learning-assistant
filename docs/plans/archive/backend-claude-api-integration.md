# バックエンド実装・Claude API連携プラン

## 目的・背景

[docs/specs/app-spec.md](../specs/app-spec.md) 5.2章の通り、OCR・翻訳はバックエンド経由で
Claude API を呼び出す設計になっているが、[ios-class-lesson-capture-screens.md](archive/ios-class-lesson-capture-screens.md)
で実装した撮影→OCR・翻訳画面は `MockOCRTranslationService`（固定文言を返すスタブ）のままで、
バックエンドが未実装。本タスクでバックエンド（ローカル開発用）を実装し、iOS側のモックを
実バックエンド連携に置き換える。

TODO.md の以下2項目を統合して対応する。
- Phase 1: 撮影 → OCR・翻訳（画面実装は完了、バックエンド連携が残課題）
- バックエンド実装・Claude API連携（OCR・翻訳のモックサービスを置き換え）

## 対応方針

### バックエンド技術スタック

- **Node.js + TypeScript + Express**、通信ログ保存に **better-sqlite3**（SQLite）を採用する。
  本リポジトリの `vibeboard/` も Node.js/TypeScript のため、開発ツールチェーンと親和性が高い。
  仕様書5.2章の通り、まずはローカル開発環境でのみ動作させる（クラウドデプロイは対象外）。
- 新規ディレクトリ `backend/`（`ios/` と同じ階層）に配置する。

### Claude API 連携

- モデルは `claude-sonnet-5`（環境変数 `ANTHROPIC_MODEL` で上書き可能）をデフォルトとする。
  OCR・翻訳は複雑な推論を要さないタスクのため、コスト・レイテンシ効率を優先し
  `thinking: {type: "disabled"}` + `output_config.effort: "low"` を使う。
- 画像（base64）+ 指示文を1回のメッセージで送り、`output_config.format`（JSON Schema による
  Structured Outputs）で `{ ocrText, translatedText }` を確実にパースできる形で受け取る。
- レスポンスの `usage.input_tokens` / `usage.output_tokens` からトークン数を取得し、
  モデルごとの単価テーブル（ハードコード、将来的な価格改定に追従が必要な旨をコメントで明記）
  でコストを概算する。

### API設計

- `POST /api/ocr-translate`
  - リクエスト: `{ imageBase64: string, mediaType: "image/jpeg" | "image/png", targetLanguage: string }`
  - レスポンス: `{ ocrText: string, translatedText: string, translationLanguage: string }`
  - 失敗時は 500 + `{ error: string }`
- 通信ログ（SQLite `requests` テーブル）に以下を保存する
  - id, created_at, image_filename（`backend/data/images/` に保存）, target_language,
    ocr_text, translated_text, model, input_tokens, output_tokens, cost_usd,
    status（success/error）, error_message, latency_ms
- `GET /admin`: 直近の通信ログ一覧をサーバーサイドレンダリングの素朴なHTMLで表示する
  （画像サムネイル・OCR結果・翻訳結果・トークン数・コストの対応、仕様書5.2章の要件）
  - `GET /admin/logs/:id/image`: 保存画像を配信する静的っぽいルート
- `GET /health`: 死活監視用

### iOS側の変更

- `RemoteOCRTranslationService`（新規）: `OCRTranslationService` プロトコルを実装し、
  `PhotoStorage` から画像を読み込んでbase64化 → `POST /api/ocr-translate` → レスポンスを
  `Photo` に反映する。ネットワークエラー・サーバーエラー時は `processingStatus = .failed` にする。
- バックエンドのベースURLは `@AppStorage("backendBaseURL")`（デフォルト `http://localhost:8787`）
  で保持する。シミュレータはホストの `localhost` にそのまま到達できるが、実機は無線LAN経由で
  Macのバックエンドに接続する必要があるため（[run-on-device.sh](../../ios/run-on-device.sh) と
  同様の実機検証フロー）、`SettingsView` に簡易的な「サーバーURL」入力欄を追加する
  （母語設定など他のプレースホルダー項目は今回のスコープ外のまま残す）
- `CaptureView`: `MockOCRTranslationService()` を `RemoteOCRTranslationService()` に置き換える
- `PhotoDetailView`: 失敗時（`processingStatus == .failed`）に「再試行」ボタンを追加する
  （data-model.md に「failed: 失敗（再試行可能）」と明記されている挙動を満たす）
- `Info.plist`（`ios/project.yml`）に `NSAppTransportSecurity` の `NSAllowsArbitraryLoads` を
  追加する（ローカル開発用バックエンドがHTTP/非TLSのため。本番クラウド化する際に見直す）

### 秘密情報の扱い

- `ANTHROPIC_API_KEY` は `backend/.env`（gitignore対象）で管理する。
  `backend/.env.example` をリポジトリに含め、必要な環境変数を明示する。

## 影響範囲

- 新規: `backend/`（`package.json`, `tsconfig.json`, `src/{index,config,db,claude,admin}.ts` 等）
- 新規: `ios/.../Sources/Services/RemoteOCRTranslationService.swift`
- 変更: `ios/.../Sources/Views/CaptureView.swift`（実サービスへの切り替え）
- 変更: `ios/.../Sources/Views/PhotoDetailView.swift`（再試行ボタン）
- 変更: `ios/.../Sources/Views/SettingsView.swift`（サーバーURL入力欄）
- 変更: `ios/project.yml`（NSAppTransportSecurity追加）
- 変更: `TODO.md` / `DONE.md`
- `.gitignore` へ `backend/node_modules/`, `backend/.env`, `backend/data/` を追加

## テスト方針

- バックエンド: `cd backend && npm run build`（`tsc --noEmit` 相当）が通ること。
  `curl` でサンプル画像（base64）を `POST /api/ocr-translate` に送り、正常系・
  APIキー未設定時のエラーハンドリングを確認する。`/admin` がログを表示することを確認する。
- iOS: `cd ios && xcodegen generate` → `xcodebuild build` が通ること。
  シミュレータで（`/run` スキル使用）撮影 → バックエンド接続 → 結果表示のフローを確認する。
  実際の Claude API 呼び出し確認には `ANTHROPIC_API_KEY` が必要なため、キーが無い場合は
  ネットワーク結線・エラーハンドリング（サーバー未起動時に `failed` 表示になること等）の
  確認にとどめ、実キーでの動作確認はAkiraに委ねる旨を明記する。

## Phase / Step

- Phase 1: バックエンド実装（Express + SQLite + Claude API連携）
- Phase 2: 管理画面（通信ログ一覧・画像/OCR/翻訳/トークン・コスト表示）
- Phase 3: iOS側をモックから実バックエンド連携に置き換え（Settingsのサーバー設定含む）
- Phase 4: 動作確認（ビルド・簡易テスト）
