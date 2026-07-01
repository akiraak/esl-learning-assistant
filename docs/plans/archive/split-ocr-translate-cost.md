# コスト計算式をOCR分・翻訳分・合計に分ける

## 目的・背景

[[translate-model-selection]]でOCRと翻訳を別モデル（Sonnet/Haiku）の2回のAPI呼び出しに分割した際、
`cost_usd` は合計値のみをDBに保存していた。OCR分・翻訳分それぞれのコストも別々に見えるようにしたい。

## 対応方針

### Step 1: DBにOCR分・翻訳分のコスト列を追加する

- `backend/src/db.ts` の `requests` テーブルに `ocr_cost_usd REAL NOT NULL DEFAULT 0` と
  `translate_cost_usd REAL NOT NULL DEFAULT 0` を追加する（`cost_usd` は合計として維持）。
- 既存DBには起動時のカラム存在チェックで `ALTER TABLE ADD COLUMN` する後方互換マイグレーションを追加する。
- `RequestLogInput`/`RequestLogRow` にも `ocrCostUsd`/`translateCostUsd` を追加し、INSERT文を更新する。

### Step 2: index.tsでOCR分・翻訳分のコストを個別に計算して保存する

- `backend/src/index.ts` の成功時処理で `estimateCostUsd` をOCR分・翻訳分それぞれ変数として保持し、
  `costUsd = ocrCostUsd + translateCostUsd` を算出。3つとも `insertRequestLog` に渡す。
- エラー時は既存通り0のまま。

### Step 3: adminの一覧・詳細ページでOCR分・翻訳分・合計を表示する

- `backend/src/admin.ts` の一覧行・詳細ページのコスト表示を
  「OCR: $x.xxxxx / 翻訳: $x.xxxxx / 合計: $x.xxxxx」の3行（または1行区切り）表示に変更する。

## 影響範囲

- `backend/src/db.ts`
- `backend/src/index.ts`
- `backend/src/admin.ts`

## テスト方針

- `npm run build` でビルド確認。
- `run-server.sh` で再起動後、既存ログがエラーなく表示されること（マイグレーション確認）。
- 実画像を `/api/ocr-translate` に投げ、OCR分・翻訳分・合計コストがそれぞれ正しい値で
  `/admin` 一覧・詳細に表示されることを確認する。
