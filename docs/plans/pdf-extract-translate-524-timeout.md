# PDF 文字起こし・翻訳の HTTP 524（Cloudflare タイムアウト）調査・対策

## 目的・背景

PDF ファイルの文字起こし＋翻訳を実行すると、アプリに `Server Error (HTTP 524)` が表示される。

HTTP 524 は Cloudflare 固有のエラーで、「オリジンサーバーへの接続はできたが、タイムアウト時間内
（デフォルト 100 秒）に HTTP レスポンスが返ってこなかった」ことを意味する。
つまりサーバーが落ちているのではなく、**処理に時間がかかりすぎている**のがほぼ確実な原因。

```
アプリ → Cloudflare → サーバー → LLM API(文字起こし+翻訳) → 応答
                ↑
        ここで100秒待って諦める(524)
```

### 実装上の裏付け

- 該当エンドポイントは `POST /api/document-extract-translate`（`backend/src/index.ts:343`）
- ハンドラ内で `await extractAndTranslateDocument(...)` の完了を待ってからレスポンスを返す
  **同期設計**になっている（`backend/src/documentExtract.ts`）
- スキャン PDF は Claude に document ブロックで丸ごと渡して OCR＋翻訳を 1 回で行う。
  `DOCUMENT_MAX_TOKENS = 16384` と出力上限が大きく、ページ数が多い PDF では
  LLM 応答だけで 100 秒を超えることは十分ありうる
- サーバー側では処理が正常に完了していても、Cloudflare が先に切断してアプリには 524 が返る

## 対応方針

### Phase 1: 原因確定（調査）

1. **サーバーログを確認する** — `backend/data/server.log` で 524 発生時刻のリクエストを追う。
   `document-extract-translate: start` の後、100 秒以降に `success ... latencyMs=...` が
   出ていれば「処理時間超過」で確定
2. **処理時間を計測する** — Cloudflare を経由せずオリジンへ直接 curl して所要時間を測る
3. **PDF サイズとの相関を確認する** — 小さい PDF（1〜2 ページ）なら成功するか試す。
   成功すればタイムアウト説が裏付けられる

### Phase 2: 対策の選定・実装（推奨順）

1. **非同期処理化（根本対策）**
   - リクエスト受付時に即座にジョブ ID を返す（202 Accepted）
   - アプリ側はポーリングか SSE で完了を待つ
   - 処理時間の制約から完全に解放される
2. **分割処理** — PDF をページ単位・チャンク単位で処理し、1 リクエストを 100 秒以内に収める
   （`documentExtract.ts` のコメントにも「将来: streaming＋分割。§9.1」とあり既知の課題）
3. **ストリーミングレスポンス** — LLM 出力をストリーミングで返せば最初のバイトが早く届き
   524 を回避できる
4. **Cloudflare 設定の変更（非推奨）** — タイムアウト延長は Enterprise プランのみ。
   該当エンドポイントだけプロキシを外す（DNS グレークラウド）手もあるが保護がなくなる

Phase 1 の結果を踏まえて Phase 2 の方式を決定する。

## Phase 1 調査結果（2026-07-21）

本番サーバー（g3plus）の `server.log` と保存済み文書ファイルから原因を確定した。

- 失敗したのは **13 ページのスキャン PDF（テキスト層なし、6.9MB）**。2026-07-21 に 2 回試行し
  いずれも失敗（`1784670870911-….pdf` / `1784671097291-….pdf`）
- サーバー処理時間は **159 秒 / 152 秒** — Cloudflare の 100 秒を大幅に超過しており、
  アプリに 524 が返った原因はタイムアウトで確定
- さらに **サーバー側でも処理自体が失敗**していた:
  `error=Unterminated string in JSON at position 34962`。
  13 ページぶんの OCR＋翻訳の出力が `DOCUMENT_MAX_TOKENS = 16384` の上限で途中切断され、
  `callStructured` の `JSON.parse` が失敗したもの。**524 を回避しても現状のままでは完走しない**
- 過去の成功例はいずれも小さい/テキスト層ありの文書（テキスト層あり 2.1MB PDF: 52 秒で成功、
  1 ページスキャン PDF: 5 秒で成功）で、サイズ相関も裏付けが取れた

→ 対策には「**非同期化**（524 の根本対策）」と「**ページ分割 OCR**（出力トークン上限対策）」の
**両方が必要**。

## Phase 2 実装方針（決定）

### Step 1: スキャン PDF のページ分割 OCR（backend）

- `pdf-lib` を追加し、スキャン PDF を 1 ページずつの PDF に分割する
  （`splitPdfIntoPages(fileBuffer): Promise<Buffer[]>`）
- ページごとに既存の OCR＋翻訳呼び出し（`DOCUMENT_OCR_SCHEMA`）を並列実行
  （同時実行数 4 程度、SDK 標準リトライに任せる）し、ページ順に `\n\n` で結合する
- 1 ページあたりの出力は数千トークンに収まるため 16384 上限の切断が起きなくなり、
  並列化で処理時間も短縮される
- 同期エンドポイント経由でも恩恵を受けられるよう `extractAndTranslateDocument` 内で行う

### Step 2: 非同期ジョブ API（backend）

- `POST /api/document-extract-translate/jobs` — バリデーション後すぐ 202 で `{jobId}` を返し、
  処理はバックグラウンドで実行
- `GET /api/document-extract-translate/jobs/:jobId` — `{status: "processing"}` /
  `{status: "success", extractedText, translatedText, translationLanguage}` /
  `{status: "failed", error}`。不明 ID は 404
- ジョブはメモリ上の Map で管理（単一インスタンス・短命なので十分）。TTL 30 分で掃除。
  完了時の課金記録（`insertDocumentLog`）は同期版と共通の実行関数に集約する
- 既存の同期 `POST /api/document-extract-translate` は旧アプリ互換のため残す
  （デプロイは backend 先行の従来運用）

### Step 3: iOS のポーリング対応

- `BackendAPI` に GET ヘルパーを追加（2xx を成功として扱う）
- `RemoteDocumentExtractTranslateService` をジョブ投入＋ポーリング
  （3 秒間隔・最長 15 分）に変更。既存の `processingStatus` 状態遷移はそのまま

### Step 4: テスト・検証

- backend: ページ分割・並列実行ヘルパー・ジョブストアの単体テストを追加、既存テストを維持
- 実際に 524 を起こした 13 ページ PDF でローカル end-to-end（ジョブ投入→完了取得）を確認

## 実装・検証結果（2026-07-21）

Step 1〜3 実装済み。検証状況:

- backend 単体テスト 57 件パス（ページ分割・並列ヘルパー・ジョブストアの新規テスト含む）
- iOS ビルド成功・`DocumentExtractTranslateServiceTests` パス
- 実際に 524 を起こした本番の 13 ページ PDF で確認:
  - `splitPdfIntoPages` が 13 個の正常な単一ページ PDF（各 290〜817KB）に分割できる
  - ジョブ API はローカルで **受付 0.04 秒・HTTP 202** → ポーリングで状態取得まで疎通
    （processing→failed の遷移・エラーメッセージ伝搬も確認）
- **残り**: Claude 呼び出し込みの完走確認。ローカル `backend/.env` の `ANTHROPIC_API_KEY` が
  無効（本番キーとハッシュ不一致＝ローテーション済みの旧キーと思われる）で、Claude API が
  401 を返すため保留。ローカルキー更新後に再実行するか、本番デプロイ後に実機アプリで確認する
- 補足: 同期設計の他エンドポイントの本番最大レイテンシは transcribe-translate 38 秒 /
  ocr-translate 29 秒で、現状 100 秒の心配はない（必要になれば同じジョブ API 方式を流用できる）

## 影響範囲

- `backend/src/index.ts` — `/api/document-extract-translate` エンドポイント
- `backend/src/documentExtract.ts` — 抽出・翻訳の実処理（非同期化 / 分割時に変更）
- iOS アプリ側の文書取り込みフロー — 非同期化する場合はジョブ ID ポーリング等の
  クライアント対応が必要
- 画像 OCR（`ocrTranslate.ts`）も同じ同期設計なら同種のリスクがあるため、調査時に確認する

## テスト方針

- 小さい PDF（1〜2 ページ）と大きい PDF（多ページ・スキャン）で成功／失敗の再現を取る
- オリジン直叩き curl で処理時間を計測し、100 秒閾値との関係を記録する
- 対策実装後、524 が再現していた PDF で完走することを実機アプリから確認する
- 既存の `backend/test/documentExtract.test.ts` が通ることを確認し、非同期化する場合は
  ジョブ受付〜完了取得のテストを追加する
