# 単語出題に「分からない」ボタンをつける

## 目的・背景
復習クイズ（`ReviewSessionView`）の出題中、選択肢・イラスト選択・タイピングのいずれの形式でも
「分からない」ときに当てずっぽうで答えるしかない。分からないことを明示して即座に正解を表示できる
ボタンを追加し、学習効率と体験を上げる。

## 対応方針
- `ReviewSessionView` の `questionView` で `answerArea` の直下、`feedback == nil` のときだけ
  「分からない」ボタンを表示する（全形式共通で1箇所に置く）。
- 押下時は **不正解扱い**で `recordAnswer(isCorrect: false, correctAnswer:)` を呼び、正解を提示する。
  - 選択肢を選ばせないので `selectedChoiceIndex` は nil のまま → 赤ハイライトは出ず、正解のみ緑表示。
  - 既存の不正解フロー（`ReviewScheduler.answered(isCorrect: false)`）に乗るため、習熟度 −25% /
    step リセット / 当日再出題という挙動は通常の誤答と同じ。
- 正解文字列は形式ごとに算出するヘルパー `correctAnswer(for:)` を追加。
  - `.choices` / `.illustrationChoices` → `options[correctIndex]`
  - `.typing` → `spec.acceptedAnswers.first ?? item.word.text`

## 影響範囲
- `ios/ESLLearningAssistant/Sources/Views/ReviewSessionView.swift` のみ（View 追加 + 解答処理関数追加）。
- データモデル・スケジューラは変更なし（既存の不正解パスを再利用）。

## テスト方針
- ビルド確認（xcodegen 生成物なので手動 pbxproj 編集なし）。
- 各出題形式で「分からない」→ 正解表示 → Next の流れを実機/シミュレータで確認。
- accessibilityIdentifier `reviewDontKnowButton` を付与し、将来の UI テストに備える。
