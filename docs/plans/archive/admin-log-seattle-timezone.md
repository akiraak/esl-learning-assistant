# 管理画面のログ時間をシアトルのタイムゾーンにする

## 目的・背景

DB のタイムスタンプ（`created_at` / `updated_at`）は `new Date().toISOString()` による UTC の ISO 8601 文字列で保存されており、管理画面（`backend/src/admin.ts`）ではその文字列をそのまま表示している。実際の利用地であるシアトルの時刻（America/Los_Angeles、DST 自動対応）で読めるようにする。

## 対応方針

- `backend/src/admin.ts` に表示用フォーマッタ `formatSeattleTime(isoUtc: string)` を追加する
  - `Intl.DateTimeFormat`（ロケール `sv-SE`、`timeZone: "America/Los_Angeles"`）で `YYYY-MM-DD HH:mm:ss` 形式に整形
  - タイムゾーン略称（PST/PDT）を付記して UTC と混同しないようにする
  - パース不能な文字列は元の値をそのまま返す（フォールバック）
- 管理画面の全タイムスタンプ表示箇所を `formatSeattleTime()` 経由に変更する
  1. OCR・翻訳ログ一覧（`/admin`）の日時
  2. OCR・翻訳ログ詳細（`/admin/logs/:id`）の日時
  3. 単語情報ログ一覧（`/admin/word-info`）の日時
  4. 単語情報ログ詳細（`/admin/word-info/:id`）の日時
  5. 単語一覧（`/admin/words`）の作成日時・更新日時
  6. 単語詳細（`/admin/words/:id`）の作成日時・更新日時
  7. TTS一覧（`/admin/tts`）の作成日時

## 影響範囲

- `backend/src/admin.ts` のみ（表示層の変更）
- DB の保存形式（UTC ISO）は変更しない。ソート等は引き続き保存値で行われるため影響なし

## テスト方針

- `npx tsc --noEmit`（または build）で型チェック
- サーバを起動し、各管理画面ページで日時がシアトル時刻（PST/PDT 付き）で表示されることを確認
