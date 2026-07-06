# 単語出題の頻度・習熟度増減幅の変更

## 目的・背景

単語復習の間隔反復スケジュールを、より短い初期間隔に変更する。あわせて1問正解あたりの習熟度増減幅を緩め、クリアまでの正解回数を増やす。

- 復習間隔: `[3, 7, 14, 30, 90]` 日 → `[1, 2, 3, 7, 14, 30, 90]` 日（7日の後は従来の14→30→90を引き継ぎ、最終ステップ到達後は90日を維持）
- 1問解答での習熟度増減幅: 25% → 20%（クリアまで4連続正解 → 5連続正解）

## 対応方針

`ReviewScheduler.swift` の2つの定数を変更する。ロジック（`answered` / `isDue` / clamp）は配列長・増減幅に依存せず一般化されているため、定数変更のみで成立する。

- `stepIntervalsInDays = [1, 2, 3, 7, 14, 30, 90]`
- `masteryDeltaPercent = 20`

あわせて doc コメント（25% / 3日 / 4連続正解などの記述）を実値に合わせて更新する。

## 影響範囲

- `ios/.../Support/ReviewScheduler.swift` — 定数2つ + コメント
- `ios/.../Views/ReviewSessionView.swift` — コメントの「+25% / −25%」を「+20% / −20%」へ
- `ios/.../Models/Word.swift` — `masteryPercent` の doc コメント
- `ios/.../Views/WordDetailView.swift` — `stepIntervalsInDays` を参照するデバッグ表示（配列長依存だが動作は問題なし、変更不要）
- テスト:
  - `ReviewSchedulerTests.swift` — 間隔・増減幅・クリア回数の期待値を更新
  - `WordReviewStatePersistenceTests.swift` — 正解1回後の `masteryPercent` 25 → 20

## テスト方針

`ReviewSchedulerTests` / `WordReviewStatePersistenceTests` を新しい定数に合わせて更新し、`xcodebuild test` で確認する。

## 補足

既存の保存済み `stepIndex`（旧配列前提で最大4）は `clampedStep` により新配列の最終インデックス（3）に丸められるため、マイグレーション不要。
