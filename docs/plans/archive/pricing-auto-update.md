# AI料金表の自動更新と管理画面「システムログ」ページ

## 目的・背景

OCR・翻訳・単語情報（今後はTTSも）の料金計算は `backend/src/pricing.ts` のハードコード単価表に依存しており、
単価改定に気づけない。単価の取得を自動で定期実行（起動時＋24時間ごと）し、
チェックが走ったこと・結果（成功／失敗／変更なし）を管理画面で確認できるようにする。

表示先は料金専用ページではなく、**汎用の「システムログ」ページ**を新設してそこにテキストで流す。
料金チェック以外のサーバイベントも今後同じページに記録できる汎用構造にする。

## データソース

LiteLLM がコミュニティ管理している機械可読の価格表を使う（Anthropic / Google に公式の価格APIは無い）:

```
https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json
```

- 事前検証済み（2026-07-02）: 使用中の全モデルのエントリが存在する
  - `claude-sonnet-5` / `claude-opus-4-8` / `claude-haiku-4-5` — `input_cost_per_token` / `output_cost_per_token` が現行ハードコード表（$3/$15, $5/$25, $1/$5 per 1M）と完全一致
  - `gemini-2.5-flash-preview-tts` / `gemini-2.5-pro-preview-tts` — エントリはあるが、**Google 公式のTTS価格（audio output token 単価）と食い違う疑いがある**（例: flash-tts の output が $2.50/1M と表記され、公式のオーディオ出力 $10/1M と乖離）
- 単価は per-token（USD）なので ×1,000,000 して per-1M に変換する

### 信頼性の割り切り

- 外部ソースが落ちている・値が壊れている場合に備え、**現行のハードコード表を既定値（フォールバック）として温存**し、取得値は検証ガードを通ったものだけ採用する
- 検証ガード: 数値が正であること、既定値からの乖離が10倍以内であること。ガードに落ちたモデルは既定値を使い続け、失敗としてログに記録する
- Gemini TTS 2モデルは上記の食い違い疑いがあるため、実装時に Google 公式ページと突き合わせ、LiteLLM 側が信用できないと判断したら自動更新の対象外（既定値固定）とする

## 全体構成

```
起動時 + 24時間ごと
  pricingSync.ts ── fetch LiteLLM JSON
       │  対象モデル抽出 → 検証ガード → per-1M変換 → 前回適用値と比較
       ├─ 成功: currentPricing（メモリ）更新 + pricing_state 保存
       │        + system_logs に「料金表更新チェック: 成功（変更なし／変更あり: 詳細）」
       └─ 失敗: system_logs に「料金表更新チェック: 失敗（理由）」（currentPricing は維持）

estimateCostUsd() ── currentPricing を参照（無ければ DEFAULT_PRICING）

/admin/logs ── system_logs を新しい順にテキスト表示（汎用）
```

- 更新は自動のみ（手動更新ボタンは設けない）
- サーバ再起動は不要。動いているプロセス内でメモリ上の単価表を書き換えるだけ
- 再起動時は `pricing_state` の最新値から currentPricing を復元する

## 実装ステップ

### Step 1: db.ts — system_logs（汎用）と pricing_state テーブル追加

```sql
-- 汎用のシステムイベントログ。料金チェック以外のイベントも今後ここに記録する
CREATE TABLE IF NOT EXISTS system_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  category TEXT NOT NULL,          -- 例: "pricing"
  level TEXT NOT NULL,             -- info | warn | error
  message TEXT NOT NULL            -- 人間が読むテキスト（表示はこれをそのまま出すだけ）
)

-- 最後に適用した単価表（再起動時の復元と変更有無の比較に使う。1行のみ運用）
CREATE TABLE IF NOT EXISTS pricing_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  updated_at TEXT NOT NULL,
  prices_json TEXT NOT NULL        -- 採用中の per-1M 単価表のJSON
)
```

- `insertSystemLog(category, level, message)` / `listRecentSystemLogs(limit)` を追加
- `getPricingState()` / `savePricingState(pricesJson)` を追加
- チェック実行のたびに必ず system_logs へ1行記録する（変更なしの成功も含む）。「24時間ごとのチェックが本当に走っているか」をログページで確認できるようにするのが目的

### Step 2: pricing.ts — 動的単価表への差し替え

- 現行の `PRICING_PER_MILLION_TOKENS` を `DEFAULT_PRICING` にリネームし既定値として温存（コメントに「自動更新のフォールバック」であることを明記）
- モジュール内可変の `currentPricing`（初期値 = DEFAULT_PRICING のコピー）を持ち、`estimateCostUsd` はこれを参照する（シグネチャ不変、呼び出し元の修正不要）
- `applyFetchedPricing(rawJson)` を追加: 対象モデルの抽出・per-1M変換・検証ガード → 採用結果を返す

### Step 3: pricingSync.ts（新規）— 取得と定期実行

- `fetchAndApplyPricing()` — fetch（タイムアウト30秒）→ `applyFetchedPricing` → `pricing_state` の前回値と比較して変更有無を判定 → state 保存 → system_logs に記録
  - ログメッセージ例:
    - `料金表更新チェック: 成功（変更なし）`
    - `料金表更新チェック: 成功（変更あり: claude-sonnet-5 input $3.00→$2.50）`
    - `料金表更新チェック: 失敗（HTTP 503 / タイムアウト / 検証ガード: ...）`
- `startPricingSync()` — 起動時に `pricing_state` から復元 → 即時1回実行 → `setInterval` で24時間ごと。`unref()` してプロセス終了を妨げない
- ネットワーク断・GitHub障害時もサーバ本体は影響を受けない（catch して記録するだけ）

### Step 4: index.ts — 起動時にスケジューラ開始

- サーバ listen 後に `startPricingSync()` を呼ぶ（1行＋import）

### Step 5: admin.ts — 「システムログ」ページ新設

- `navLinks` の型・リンクに `logs`（表示名「システムログ」）を追加（5タブ目。既存の「OCR・翻訳ログ」「単語情報ログ」はAPIリクエストログなので名前で区別する）
- `GET /admin/system-logs`: `listRecentSystemLogs(100)` を新しい順に表示するだけのシンプルなページ
  （実装時変更: 当初案の `/admin/logs` は既存の OCR ログ詳細 `/admin/logs/:id` と紛らわしいため `system-logs` に変更）
  - 各行: 日時（シアトル時刻）／カテゴリ／メッセージ のテキスト表示
  - level に応じた文字色（warn: 黄土色, error: 赤）だけ付け、集計・グラフ・専用セクション等は作らない

### Step 6: 動作確認

- `npm run build`（tsc）が通ること
- サーバ起動 → システムログページに「料金表更新チェック: 成功（変更なし）」が記録されること
- チェック間隔を一時的に短く（例: 1分）してインターバル実行がログに積まれることを確認し、24時間に戻す
- URLを一時的に壊して「失敗（...）」がログに記録され、料金計算は既定値で動き続けることを確認し、戻す
- 既存の OCR/単語情報の料金計算結果が従来と一致すること（Claude単価はソースと既定値が同値なので変化しないはず）

## 影響範囲

- `backend/src/db.ts` — テーブル・ヘルパー追加のみ（既存テーブル変更なし）
- `backend/src/pricing.ts` — 内部構造変更（`estimateCostUsd` のシグネチャは不変）
- `backend/src/pricingSync.ts` — 新規
- `backend/src/index.ts` — 起動フック1行
- `backend/src/admin.ts` — システムログページ・navLinks
- API・iOS への影響なし

## 関連

- [tts-admin-duration-cost](tts-admin-duration-cost.md) の Step 3（Gemini TTS 単価追加）は、本プラン実装後は `DEFAULT_PRICING` への追加＋自動更新対象への組み込み（または対象外指定）として行う
- 今後のサーバイベント（例: TTS合成失敗、キャッシュ自己修復）も `insertSystemLog` で同じページに記録できる
