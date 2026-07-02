# 各タブ画面トップのナビゲーションタイトル削除

## 目的・背景

3タブ構成の各画面（Lessons / Words / Settings）のトップに表示されるナビゲーションタイトルが不要なため削除する。タブバーで現在地が分かるため、タイトル表示は冗長。

## 対応方針

各ビューの `.navigationTitle(...)` を削除する。

- `ios/ESLLearningAssistant/Sources/Views/LessonsView.swift` — `.navigationTitle("Lessons")`
- `ios/ESLLearningAssistant/Sources/Views/WordsView.swift` — `.navigationTitle("Words")`
- `ios/ESLLearningAssistant/Sources/Views/SettingsView.swift` — `.navigationTitle("Settings")`

Words 画面はツールバーボタン（追加・AI一括生成）と検索バーがあるため、ナビゲーションバー自体は残る（タイトルのみ非表示になる）。

## 影響範囲

- 上記3ビューのみ。下層画面（Add Word / Photo Detail 等）のタイトルは変更しない。
- タイトル削除により、下層画面からの戻るボタンのラベルが「Back」表記になる。

## テスト方針

- ビルドが通ることを確認する（xcodebuild）。
- シミュレータで各タブのトップにタイトルが表示されないことを目視確認する。
