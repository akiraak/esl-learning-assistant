# 管理画面: AIモデル料金ページの作成

## 目的・背景

AIモデルの単価は `pricing_state`（DB）+ 定期自動更新で管理しているが、現在の適用値を
確認するには DB を直接見るか system_logs の変更ログを追うしかない。
管理画面に料金ページを追加し、適用中の単価・取得元・最終更新を一覧できるようにする。

## 対応方針

`backend/src/admin.ts` に `/admin/pricing` ページを追加する。

- サイドバーに「AI料金」を追加（TTS一覧とシステムログの間）
- サマリーカード: 登録モデル数 / 最終更新日時（`pricing_state.updated_at`）
- 料金テーブル: モデル / 取得元（LiteLLM・Google公式ページ）/ input・output 単価（per 1M, USD）
  / フォールバック既定値。既定値と異なる適用値は視覚的に分かるようにする
- 更新履歴: system_logs の category=pricing の直近10件を表示
- 「今すぐ更新」ボタン: POST `/admin/pricing/refresh` で LiteLLM と Google 公式ページの
  チェックを即時実行（`fetchAndApplyPricing` / `fetchAndApplyTtsPricing`）してリダイレクト

## 影響範囲

- `backend/src/admin.ts` のみ（ページ・ナビ・refreshルート追加）
- `pricing.ts` は `DEFAULT_PRICING` / `DEFAULT_TTS_PRICING` / `getCurrentPricing` を参照するだけ
- DB スキーマ変更なし

## テスト方針

- ビルド + サーバー再起動後、`/admin/pricing` を実データで目視確認
  （単価表示・既定値との差・更新履歴・ナビのアクティブ表示）
- 「今すぐ更新」ボタンを実行し、system_logs に2行追加され最終更新日時が変わることを確認
