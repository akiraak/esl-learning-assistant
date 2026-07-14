# 単語出題のバグ調査用: 出題時に識別できるIDを表示する

## 目的・背景

単語復習クイズ（`ReviewSessionView`）の出題に何らかのバグが報告されている。
どの単語・どの出題形式で問題が起きているのかを画面から即座に特定できるように、
出題時に「識別できるID」を小さなキャプションとして表示する。

## 対応方針

- 出題画面（`ReviewSessionView.questionView`）の出題文（instruction）の上に、
  デバッグ用の識別キャプションを1行表示する。
- 表示内容は **単語text ＋ 出題形式コード**（例: `🐞 run · tc7`）。
  - `item.word.text`（登録単語）＋ `item.question.format.rawValue`（tc7/vc2 等、
    サーバ `quiz_questions.format` と一致する形式コード）。
  - この2つで、サーバ保存問題（単語text＋format でキー付け）を直接引ける最有力の識別子になる。
  - 出題形式によっては答えの単語が見えてしまうが、バグ調査優先で許容する（ユーザー合意済み）。
- スタイルは目立ちすぎない caption。単語タップ登録の対象にしない（`TappableEnglishText`
  ではなく plain `Text`/`Label` を使い、誤登録を防ぐ）。
- UI テスト等から拾えるよう `accessibilityIdentifier("reviewDebugIdentity")` を付与する。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/ReviewSessionView.swift`
  - `questionView(_:)` の ScrollView 先頭にキャプションを追加。
  - 表示用の小さなヘルパー View を1つ追加。
- モデル・スケジューリング・サーバ通信には触れない（表示のみの追加）。

## テスト方針

- ビルドが通ること（XcodeGen プロジェクト、`xcodebuild` でコンパイル確認）。
- シミュレータで復習セッションを開始し、出題文の上に `単語 · 形式コード` が出ることを確認。
