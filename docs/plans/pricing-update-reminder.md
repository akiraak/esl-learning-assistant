# 管理画面にAI料金表の定期更新を促す表示を入れる

## 目的・背景

OCR・翻訳・単語情報の料金計算は `backend/src/pricing.ts` の単価表（ハードコード）に依存している。
AIの単価は値下げ・改定されることがあるが、現状は単価表をいつ確認・更新したかの記録がなく、
古い単価のまま料金を計算し続けても気づけない。

単価表の「最終更新日」をコードに記録し、一定期間が経過したら管理画面に更新リマインドを表示することで、
定期的な価格確認を促す。

## 対応方針

- 単価表の隣に最終更新日を定数としてハードコードする（DBや外部ファイルは使わない。単価表自体がコード内にあるため、更新日も同じファイルで管理するのが最も自然で、単価を更新するときに同じ diff で日付も更新される）
- 鮮度判定ロジックは `pricing.ts` 側に置き、管理画面はそれを表示するだけにする
- 表示は管理画面の主要4ページ共通ヘッダ（`navLinks`）に組み込む
  - 期限内: 小さく「料金表最終更新: YYYY-MM-DD（N日前）」を常時表示（更新日が見えること自体がリマインドになる）
  - 期限超過（90日）: 警告色のバナーで「料金表の更新からN日経過しています。最新価格を確認してください」＋各社の価格ページへのリンクを表示

## 実装ステップ

### Step 1: pricing.ts — 最終更新日と鮮度判定を追加

- `export const PRICING_LAST_UPDATED = "YYYY-MM-DD";` を単価表の直上に追加（実装日の日付で初期化）
- 単価表のコメントに「**単価を変更したら PRICING_LAST_UPDATED も更新すること**」を明記
- 鮮度チェック期間 `PRICING_STALE_AFTER_DAYS = 90` を定数化
- ヘルパーを追加:
  ```ts
  export function getPricingFreshness(): {
    lastUpdated: string;   // "YYYY-MM-DD"
    daysSince: number;     // 経過日数（切り捨て）
    isStale: boolean;      // daysSince >= PRICING_STALE_AFTER_DAYS
  }
  ```
- 価格参照先URLも定数化して export する（バナーのリンクに使用）:
  - Anthropic: https://platform.claude.com/docs/en/pricing
  - Google (Gemini): https://ai.google.dev/pricing
    （Gemini TTS 単価は [tts-admin-duration-cost](tts-admin-duration-cost.md) プランで追加予定。先にこちらを実装してもリンクは載せておいて問題ない）

### Step 2: admin.ts — 共通ヘッダに鮮度表示を追加

- `pricingBanner()` ヘルパーを追加し、`navLinks()` の返り値に含める（OCR・翻訳ログ / 単語情報ログ / 単語一覧 / TTS一覧 の4ページ全てに出る）
- 期限内の表示例:
  `料金表最終更新: 2026-07-02（12日前）` … グレーの小さめテキスト
- 期限超過の表示例（`PAGE_STYLE` に警告バナー用スタイルを追加）:
  `⚠ AI料金表の更新から 95日 経過しています。単価が改定されていないか確認してください: [Anthropic] [Google]`
  … 黄色背景のバナー（`.pricing-stale` クラス）

### Step 3: 動作確認

- `npm run build`（tsc）が通ること
- 管理画面4ページ全てに最終更新日が表示されること
- `PRICING_LAST_UPDATED` を一時的に過去日（例: 100日前）にして警告バナーが出ること・リンクが機能することを確認し、戻す

## 影響範囲

- `backend/src/pricing.ts` — 定数・ヘルパー追加（既存の `estimateCostUsd` は変更なし）
- `backend/src/admin.ts` — 共通ヘッダとスタイルのみ
- API・DB・iOS への影響なし

## テスト方針

上記 Step 3 の手動確認で足りる規模（表示のみの変更でロジックは日付差分計算だけ）。
日数計算は「UTC基準のミリ秒差 / 86,400,000 の切り捨て」とし、タイムゾーンによる±1日の揺れは許容する。
