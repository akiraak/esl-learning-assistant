# 復習クイズ: 習熟度（正解率）方式への変更

## 目的・背景

現状は 1 単語につき 1 セッション 1 問で、初回解答だけで dueDate が更新される（=1問正解でその日はクリア）。
これでは 1 単語あたりの練習量が少ないため、単語ごとに「習熟度（正解率）」を持たせ、
100% に到達して初めてクリア（次回復習日へ進む）とする。

## 仕様

### 習熟度（masteryPercent）

- 単語ごとに `WordReviewState.masteryPercent`（0〜100）を永続保存する（日をまたいで引き継ぐ）
- 1 問正解で +25%（上限 100）、不正解で −25%（下限 0）
- 不正解時は従来どおり lapse 扱い（lapseCount +1、Leitner ステップを 0 にリセット）。dueDate は変えない
- 100% に到達した時点でクリア:
  - 従来の「正解」と同じく現在ステップの間隔で dueDate を設定し、ステップを 1 つ進める（Leitner 維持: 3→7→14→30→90日）
  - masteryPercent は次周回に備えて 0 にリセットする
- クリアするまで dueDate は過去のまま → 翌日以降も出題対象に残り続ける

### セッション

- 1 セッションの対象単語は最大 **5 語**（due 単語の先頭 5 語）
- 1 セッションの出題数は最大 **10 問**
- 出題はラウンドロビン（未クリア単語のキューを回す）で、同じ単語が連続しないようにする
  （未クリアが 1 語だけ残った場合は連続を許容。そうしないと 100% に到達できない）
- 10 問未満でも対象全単語が 100% に達したらセッション終了
- reviewState への反映は毎解答（従来の「初回のみ + retry 表示のみ」を廃止。retryQueue も廃止）
- 音声は対象 5 語の全問題の audioText を開始前に一括ダウンロードする
  （従来は事前確定した問題分のみ。出題が動的になるため全問題分に変更。5 語なので件数は小さい）
  - DL 失敗した音声の問題は出題候補から除外。候補が無くなった単語はスキップ

## 影響範囲

- `ios/.../Models/Word.swift`: `WordReviewState.masteryPercent` 追加
  - **SwiftData 埋め込み Codable のため必ず nullable ストレージ + computed 既定値 0 のパターンで追加する**
    （非オプショナル追加は既存ストアのマイグレーション失敗でストアが開けなくなる）
- `ios/.../Support/ReviewScheduler.swift`: `reviewed()` を `answered()` に置き換え（習熟度反映 + クリア判定）
- `ios/.../Support/ReviewSessionPlanner.swift`: 事前確定（plan / replacingFailedAudio）を廃止し `pick` のみ残す
- `ios/.../Views/ReviewSessionView.swift`: セッションループをラウンドロビン + 10 問上限に書き換え、
  フィードバックに習熟度表示を追加、サマリーの文言調整
- `ios/.../Views/WordDetailView.swift`: Review セクションに Mastery 行を追加
- `docs/specs/data-model.md` §5 があれば習熟度の記述を追記

## テスト方針

- `ReviewSchedulerTests`: answered() の +25/−25、上下限、100% クリア時のステップ前進・dueDate 設定・
  習熟度リセット、不正解時のステップリセット & dueDate 不変を検証
- `WordReviewStateTests`: masteryPercent 無しの旧データが 0 でデコードされること、round-trip
- `ReviewSessionPlannerTests`: plan / replacingFailedAudio のテストを削除し pick のみ残す
- シミュレータで xcodebuild test を実行

## Steps

- [x] Step 1: WordReviewState に masteryPercent 追加（マイグレーション安全パターン）+ テスト
- [x] Step 2: ReviewScheduler.answered() 実装 + テスト
- [x] Step 3: ReviewSessionPlanner の縮小（pick のみ）+ テスト整理
- [x] Step 4: ReviewSessionView のセッションループ書き換え（5語・10問・ラウンドロビン・習熟度表示）
- [x] Step 5: WordDetailView に Mastery 表示、仕様書更新、全テスト実行
