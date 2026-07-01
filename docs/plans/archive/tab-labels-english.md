# タブ名の英語化

## 目的・背景

3タブ化（[tab-navigation-redesign.md](archive/tab-navigation-redesign.md)）の続き。
タブバーの表示名を日本語（レッスン/単語/設定）から英語に変更する。

- レッスン → Lessons
- 単語 → Words
- 設定 → Settings

画面内のナビゲーションタイトルや本文は日本語のまま（変更対象はタブバーのラベルのみ）。

## 対応方針

1. `ContentView.swift` のタブ `Label` を英語表記に変更
2. UIテストのタブボタン参照（`testTabsAreVisible` / `testWordAddFlow`）を追随
3. `docs/specs/screen-design.md` の「0. 全体ナビゲーション」の表記を更新

## 影響範囲

- iOS: `ContentView.swift`、`ESLLearningAssistantUITests.swift`
- docs: `screen-design.md`

## テスト方針

- シミュレータでUIテスト（タブ表示・単語追加フロー）を再実行して確認
