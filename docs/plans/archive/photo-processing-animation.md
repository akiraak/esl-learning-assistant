# 処理中のアニメーション演出（レッスン画面・コンテンツ詳細画面）

## 目的・背景

Phase 1 で OCR/翻訳を非同期化し、写真追加後は即レッスン画面へ戻るようになった。処理はバックグラウンドで進むため、進捗が「動いている」ことを視覚的に伝えるアニメーション演出を入れて、待ち時間の体感を良くする。対象は 2 画面:

1. **レッスン画面（`LessonsView` の `PhotoRow`）** — 一覧の各行の status ラベル。
2. **コンテンツ詳細画面（`PhotoDetailView`）** — 写真詳細の処理中表示。

## 現状整理

- `PhotoProcessingStatus`: `pending / processing / completed / failed`。
- 非同期化後の状態遷移: 追加=`pending` → `translateAllPending` が順次 `process()` で `.processing` にして通信 → `.completed`/`.failed`。逐次処理なので、順番待ちの写真は一時的に `pending` のまま。
- **`PhotoRow.statusLabel`**（`LessonsView.swift`）: 静的な `Label`。`processing` は `hourglass`、`pending` は `clock`。アニメーション無し。
- **`PhotoDetailView` の `.processing` ケース**: 「did not finish (interrupted)」という**中断前提の静的メッセージ + retry ボタン**。非同期化後は `.processing` が「今まさに処理中」を意味する一般的な状態になったため、文言が実態と合わない。

## 対応方針

再利用可能なアニメーション部品を追加し、両画面の「処理中（pending/processing）」表示に適用する。

- **新規部品** `Sources/Views/ProcessingIndicator.swift`:
  - `pulse()` 修飾子: opacity を呼吸のように上下させる（`easeInOut` + `repeatForever(autoreverses:)`）。
  - `ShimmerSkeletonLine`: シマー（横方向に光沢が流れる）付きのプレースホルダ行。詳細画面で結果テキストの代わりに表示。
- **`PhotoDetailView`**: `.processing` を「中断メッセージ」から「アクティブな処理中演出」に作り替える。
  - `ProgressView()` + 「Processing OCR & translation…」（`pulse` 付き） + シマーのスケルトン数行。
  - ただし稀にアプリ強制終了で `.processing` のまま固まる可能性があるため、控えめな retry ボタンを残して回復手段を確保する（`translateAllPending` は pending/failed のみ対象で processing は拾わないため）。
  - `.pending` ケースも同じ演出に寄せる（開始待ちを animated に）。
- **`LessonsView` の `PhotoRow`**: `statusLabel` を `@ViewBuilder` 化。
  - `.processing`: インラインの `ProgressView()`（小）+ 「Processing」テキスト（`pulse`）。
  - `.pending`: `clock` アイコン + 「Pending」（`pulse`、順番待ちを穏やかに表現）。
  - `.completed`/`.failed`: 従来どおり静的。
- 状態変化には `.animation(_, value: photo.processingStatus)` を添えて、pending→processing→completed の切り替わりを滑らかにする。

## 影響範囲

- `Sources/Views/ProcessingIndicator.swift`（新規）
- `Sources/Views/PhotoDetailView.swift`（`.processing`/`.pending` ケース差し替え）
- `Sources/Views/LessonsView.swift`（`PhotoRow.statusLabel` のアニメーション化）
- モデル・サービス・バックエンド変更なし。SwiftData マイグレーション不要。

## テスト方針

- ビルド: `xcodegen generate` 後にビルド成功。
- 手動（`/run`）: 写真追加 → レッスン行が pending/processing の間アニメーション、completed で静止。詳細を開くと処理中はシマー演出、完了で結果表示。失敗時は従来どおり retry で回復。
