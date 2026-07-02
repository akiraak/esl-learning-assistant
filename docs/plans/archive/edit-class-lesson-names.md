# クラス名とレッスン名を編集可能に

## 目的・背景

現状、クラス（`Class.name`）とレッスン（`Lesson.title`）は作成時に名前を付けた後、変更する手段がない。
入力ミスの修正や整理のために、後から名前を編集（リネーム）できるようにする。

クラス・レッスンは SwiftData による端末内ローカル保存のみで、バックエンドは関与しない
（[app-spec.md](../specs/app-spec.md) §4）。よって iOS 側のみの変更で完結する。

## 対応方針

追加系の既存ビュー（`ClassAddView` / `LessonAddView`）をテンプレートに、編集用ビューを新設する。

1. **`ClassEditView` 新設** — `Form` + `TextField` + `.confirmationAction`（Save）。
   初期値に現在の `name` を設定。空文字は Save 不可。クラス名は追加時にも重複チェックが
   無いため、編集時もチェックしない（現状仕様と揃える）。
2. **`LessonEditView` 新設** — 同上。初期値に現在の `title`。
   `LessonAddView` の大文字小文字を区別しない同名重複チェックを移植し、
   **編集対象自身を除外**（`$0.id != lesson.id`）する。重複時は赤字フッター＋ Save 無効。
3. **編集導線を `ClassLessonSwitcherView` に追加**
   - レッスン行: `swipeActions` に「Rename」を追加 → `LessonEditView` へ遷移
   - クラスのセクションヘッダー: 既存の追加（＋）ボタンの横に鉛筆アイコン → `ClassEditView` へ遷移
4. 保存は SwiftData の `@Model` プロパティ代入（autosave）で完了。`modelContext` の明示操作は不要。

## 影響範囲

- 新規: `ios/ESLLearningAssistant/Sources/Views/ClassEditView.swift`
- 新規: `ios/ESLLearningAssistant/Sources/Views/LessonEditView.swift`
- 変更: `ios/ESLLearningAssistant/Sources/Views/ClassLessonSwitcherView.swift`（導線追加）
- バックエンド・データモデル・他画面の変更なし（名前表示箇所は SwiftUI が自動再描画）

## テスト方針

- `xcodebuild` でビルド確認
- シミュレータでの GUI 確認項目:
  - クラス名を編集 → 切り替えシート・Lessons 画面のカード表示に反映される
  - レッスン名を編集 → 同上
  - レッスン名を同クラス内の既存レッスンと同名に変更しようとすると Save 不可・エラー表示
  - 名前を変えずに Save しても問題ない（自己重複と誤判定しない）
  - 空文字・空白のみでは Save 不可
