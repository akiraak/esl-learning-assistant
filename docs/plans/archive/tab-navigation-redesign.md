# ナビゲーション3タブ化（レッスン / 単語 / 設定）

## 目的・背景

現在のタブバーは「ホーム / 単語帳 / 問題 / 設定」の4タブだが、単語帳・問題はプレースホルダのまま。
日常フローを整理し、ナビゲーションを以下の3タブに絞る。

- **レッスン**: クラスとレッスンを選択すると、教材の画像・文字起こし・翻訳、レッスンに関連付いた
  単語や問題が見られる（現ホームタブを改名・拡張。問題タブはここに統合する方針で独立タブは廃止）
- **単語**: 単語の一覧・詳細・追加が行える。追加時にレッスンを任意で指定できる（なしでも登録可能）
- **設定**: 既存の設定画面のまま（内容は未定・現状維持）

単語タブの実装に伴い、[data-model.md](../specs/data-model.md) の `Word` / `WordOccurrence` を
iOS側モデルとして追加する（TODO「Phase 2: 単語帳（登録・翻訳・復習）」のうち登録部分の前倒し。
翻訳・復習(フラッシュカード)は本タスクのスコープ外）。

## 対応方針

### Phase 1: タブ構成変更

- `ContentView.swift`: 4タブ → 3タブ（レッスン / 単語 / 設定）
- `HomeView.swift` → `LessonsView.swift` に改名（struct名・タイトルも「レッスン」へ）
- `QuizView.swift` を削除（問題はレッスンタブ内に将来統合）
- `VocabularyView.swift`（プレースホルダ）を削除し、Phase 3 の `WordsView` に置き換え
- UIテスト `testTabsAreVisible` のタブ名、`homeAddClassButton` → `lessonAddClassButton` を更新

### Phase 2: Word / WordOccurrence モデル追加

- [data-model.md](../specs/data-model.md) 5章・6章に準拠して `Word`（`WordReviewState` 埋め込み・
  `ExampleSentenceSource` enum 含む）と `WordOccurrence` を SwiftData `@Model` で追加
- `Lesson` に `wordOccurrences`（cascade delete）を追加
- `ESLLearningAssistantApp` の modelContainer にモデルを登録

### Phase 3: 単語タブ実装

- `WordsView`: 単語一覧（登録日降順）。スワイプ削除（`Word`＋`occurrences` カスケード削除）
- `WordDetailView`: 訳語・例文・品詞・文法メモ・登場レッスン一覧・復習状態の表示
- `WordAddView`: 見出し語・訳語（必須）、例文・品詞（任意）、レッスン指定（任意・「なし」可）の
  フォーム。同一 text の既存 `Word` があれば新規作成せず `WordOccurrence` のみ追加
  （data-model.md 6章のルール）

### Phase 4: レッスンタブに単語・問題セクション追加

- `LessonsView` のレッスン内容に「単語」セクションを追加（`lesson.wordOccurrences` 経由の
  重複排除済み単語一覧、タップで `WordDetailView` へ）
- 「問題」セクションはプレースホルダ表示（Question モデルは未実装のため Phase 3 タスクで対応）

### Phase 5: プロジェクト定義・ドキュメント更新と動作確認

- `project.yml` に swift-markdown-ui の packages 定義を追加
  （現状 pbxproj 直付けのため、xcodegen 再生成でパッケージ参照が消える問題の解消）
- xcodegen 再生成 → シミュレータ向けビルドで確認
- `docs/specs/screen-design.md` の「0. 全体ナビゲーション」を3タブ構成に更新

## 影響範囲

- iOS: `ContentView` / `HomeView`(改名) / `VocabularyView`(置換) / `QuizView`(削除) /
  `Lesson` / `ESLLearningAssistantApp` / 新規 `Word` `WordOccurrence` `WordsView`
  `WordDetailView` `WordAddView` / UIテスト / `project.yml`(+pbxproj再生成)
- docs: `screen-design.md`（ナビゲーション章）
- backend: 影響なし

## テスト方針

- `xcodebuild` シミュレータ向けビルドが通ること（ユニット・UIテストターゲット含む）
- SwiftData スキーマ追加はローカルDBのマイグレーション（軽量・フィールド追加のみ）で成立する想定。
  シミュレータでの起動確認は別途GUI操作可能なタイミングで行う（既存TODOの動作確認項目と同様）
