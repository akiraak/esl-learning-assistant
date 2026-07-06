# コンテンツ一覧の項目名を OCR の最初のタイトルにする

## 目的・背景

レッスンの Content セクションの一覧行（`PhotoRow`）は現在、主表示が撮影日（`capturedAt`）で内容が判別しづらい。OCR 結果の先頭に出てくるタイトル（見出し）を項目名として表示し、どのページか一目で分かるようにする。

## 現状整理

- OCR 本文 `Photo.ocrText` は **Markdown**（backend `ocrTranslate.ts`: 見出しは `#`、箇条書きは `-`、強調は `**`）。
- `PhotoRow`（`LessonsView.swift`）: 行の主表示は `Text(photo.capturedAt, style: .date)`、その下に `statusLabel`。
- OCR 未完了（pending/processing/failed）や本文なしのケースがある → タイトルが取れない。

## 対応方針

- `Photo` に表示用タイトルの computed プロパティ `contentTitle` を追加:
  - `ocrText` を行分割し、**最初の見出し行（`#`〜`######`）** の本文を返す（先頭 `#` と前後空白、インライン強調 `**`/`*`/`_`/`` ` `` を除去）。
  - 見出しが無ければ **最初の非空行**を同様に整形して返す。
  - 本文が空（OCR 未完了など）なら空文字を返す。
- `PhotoRow` の主表示を `contentTitle` に変更:
  - タイトルがあればそれを 1 行目（`lineLimit(1)`）に表示。無ければ "Untitled"。
  - 撮影日は 2 行目に降格し、`statusLabel` と同じ行に小さく併記（日付情報は残す）。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Models/Photo.swift`（`contentTitle` 追加）
- `ios/ESLLearningAssistant/Sources/Views/LessonsView.swift`（`PhotoRow` の表示変更）
- モデルのストレージ変更なし（computed のみ）。SwiftData マイグレーション不要。

## テスト方針

- ビルド成功（既存ファイル改変のみ、xcodegen 再生成不要）。
- 手動（`/run`）: 見出しのある写真は行にタイトル表示、見出しの無い写真は先頭行、OCR 未完了は "Untitled" + 日付/ステータス表示。
