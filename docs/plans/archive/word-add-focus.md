# 単語追加時に入力欄へ最初からフォーカスを当てる

## 目的・背景

単語追加シート（`WordAddView`）を開いたとき、ユーザーはまず単語を入力するのが目的なのに、
入力欄をタップしないとキーボードが出ない。開いた瞬間に入力欄へフォーカスを当てて
すぐ入力を始められるようにする。

TODO には「クラス作成、レッスン作成も同様に」とあるが、`ClassAddView` / `LessonAddView` には
既に `@FocusState` + `.onAppear` によるフォーカス処理が実装済み（コミット 70859ac 時点で存在）。
今回の対象は `WordAddView` のみで、クラス・レッスン側は実装済みであることの確認のみ行う。

## 対応方針

`WordAddView` に既存の `ClassAddView` / `LessonAddView` と同じパターンを適用する。

- `@FocusState private var isTextFocused: Bool` を追加
- 単語入力の `TextField` に `.focused($isTextFocused)` を付与
- `.onAppear { isTextFocused = true }` でシート表示時にフォーカスを当てる

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/WordAddView.swift` のみ

## テスト方針

- iOS シミュレータ向けビルドが通ることを確認する
- 単語タブ / レッスン画面から単語追加シートを開き、キーボードが自動表示されることを手動確認する
