# Gemini TTS 料金の DB 保存・定期更新対応

## 目的・背景

Gemini TTS の単価は `pricing.ts` の `STATIC_PRICING` にコード内固定で持っており、
DB（`pricing_state`）にも入らず、24時間ごとの料金自動更新（`pricingSync.ts`）の対象外。
Google が価格改定しても自動反映されないため、Claude モデルと同様に DB 保存 + 定期更新に含める。

## 取得元の調査結果（2026-07-03）

- LiteLLM の価格JSON は Gemini TTS について**公式と異なる値**を載せている
  - flash: input $0.30 / output $2.50（公式: $0.50 / $10.00）
  - pro: input $1.25 / output $10.00（公式: $1.00 / $20.00）
  - いずれも検証ガード（10倍乖離）を通過してしまうため、LiteLLM を取得元にすると誤値が採用される
- Google 公式の料金ページ https://ai.google.dev/gemini-api/docs/pricing は静的HTMLで取得可能で、
  モデルID（`gemini-2.5-flash-preview-tts` 等）のセクション内に
  `Input price … $0.50 (text)` / `Output price … $10.00 (audio)`（per 1M tokens）が含まれる

→ **Claude は従来どおり LiteLLM、Gemini TTS は Google 公式ページを取得元にする**

## 対応方針

### pricing.ts

- `STATIC_PRICING` を `DEFAULT_TTS_PRICING`（フォールバック既定値）に改名し、
  `currentPricing` の初期値を `DEFAULT_PRICING` + `DEFAULT_TTS_PRICING` のマージにする
  （`estimateCostUsd` は `currentPricing` だけを見る形に単純化）
- Google 料金ページの HTML から TTS 単価を抽出する `applyFetchedTtsPricing(html)` を追加
  - モデルIDの出現位置からセクションを切り出し、`$X (text)` / `$Y (audio)` を正規表現で抽出
  - 既存と同じ検証ガード（既定値から10倍超の乖離は不採用、失敗時は現行値維持）
- `restorePricing` は TTS モデル分も復元対象に含める

### pricingSync.ts

- `fetchAndApplyPricing`（LiteLLM / Claude）は従来どおり
- `fetchAndApplyTtsPricing`（Google 公式ページ / Gemini TTS）を追加し、
  起動時・24時間ごとの両方で実行。結果は従来と同様に `system_logs` に毎回1行記録
  （成功・変更あり warn / 失敗 error、失敗時は現行値のまま料金計算継続）
- 適用後の `savePricingState` は全モデル（Claude + TTS）を含む単価表を保存

## 影響範囲

- `backend/src/pricing.ts` / `backend/src/pricingSync.ts` のみ
- DB スキーマ変更なし（`pricing_state.prices_json` に TTS モデルのキーが増えるだけ）
- 管理画面・コスト計算の呼び出し側は変更なし

## テスト方針

- ビルド後にサーバーを再起動し、以下を確認する
  - `system_logs` に Claude / TTS 両方の更新チェック結果が記録される
  - `pricing_state.prices_json` に TTS モデルが公式値（flash $0.5/$10, pro $1/$20）で入る
  - TTS 生成コストの計算が従来どおり動く（`estimateCostUsd` のフォールバック削除の回帰確認）
