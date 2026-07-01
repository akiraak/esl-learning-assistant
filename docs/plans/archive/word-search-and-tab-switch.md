# 単語一覧の検索・レッスン単語タップでのタブ切替

## 目的・背景

Phase 2（単語帳）のうち、TODO に挙がっている以下を実装する。

- 単語一覧（前回コミットで `WordsView` として実装済み。本タスクで動作確認と仕上げ）
- 検索（単語タブで見出し語・訳語を絞り込めるようにする）
- レッスンの単語をタップしたらタブが切り替わり単語が表示されるようにする
  （現状はレッスンタブ内で `WordDetailView` にプッシュしているだけ。単語に関する操作は
  単語タブに集約する方針に合わせ、Words タブへ切り替えた上で詳細を表示する）

## 対応方針

### Step 1: 単語一覧の検索

- `WordsView` に `.searchable(text:)` を追加する
- `Word.text` / `Word.translation` の部分一致（大文字小文字を区別しない）でフィルタする
- 検索ヒット 0 件時は `ContentUnavailableView.search` を表示する
- スワイプ削除はフィルタ後の配列に対して行うよう修正する

### Step 2: レッスン単語タップ → Words タブ切替＋詳細表示

- タブ間連携用のルーター `AppRouter`（`@Observable` / `@MainActor`）を新設する
  - `selectedTab: AppTab`（`lessons` / `words` / `settings` の enum）
  - `pendingWord: Word?`（Words タブで表示すべき単語）
- `ContentView` の `TabView` に `selection` を導入し、`AppRouter` を `.environment` で注入する
- `LessonsView` の単語セクションの行を `NavigationLink` から `Button` に変更し、タップで
  `router.showWord(word)`（`pendingWord` 設定 → `selectedTab = .words`）を呼ぶ
- `WordsView` は `navigationDestination(item:)` で受け口を追加し、`pendingWord` の変化
  （`onChange`）と初回表示（`onAppear`）で詳細をプッシュして `pendingWord` をクリアする

## 影響範囲

- `ios/ESLLearningAssistant/Sources/ContentView.swift`（TabView selection・Router 注入）
- 新規: `ios/ESLLearningAssistant/Sources/Support/AppRouter.swift`
- `ios/ESLLearningAssistant/Sources/Views/WordsView.swift`（検索・外部からの詳細表示受け口）
- `ios/ESLLearningAssistant/Sources/Views/LessonsView.swift`（単語行のタップ挙動変更）

## テスト方針

- `xcodebuild` でシミュレータ向けビルドが通ることを確認する
- UI テストに「レッスンの単語タップで Words タブへ切り替わり詳細が表示される」ケースを追加する
- 既存の UI テスト（`testWordAddFlow` など）が壊れていないことを確認する
