# Lessonページの Words セクションに単語追加ボタン

## 目的・背景

Lessonページ（Lessonsタブ）の Words セクションから直接単語を追加できるようにする。
タップすると Words タブに切り替わり単語追加画面（`WordAddView`）が開く。
このとき Lesson は遷移元の Lesson に固定され、変更できない状態にする。

既存の類似パターン: Lessonページの単語行タップは `AppRouter.showWord(_:)` で
Wordsタブへ切り替え、`WordsView` が `pendingWord` を消費して詳細をpushしている。
今回も同じ「router に pending 値を積み、WordsView が消費する」方式を踏襲する。

## 対応方針

1. **`AppRouter`** (`Sources/Support/AppRouter.swift`)
   - `var pendingAddWordLesson: Lesson?` を追加
   - `func showAddWord(for lesson: Lesson)` を追加（値をセットして `selectedTab = .words`）
2. **`WordAddView`** (`Sources/Views/WordAddView.swift`)
   - `fixedLesson: Lesson?`（デフォルト nil）を init 引数に追加
   - fixedLesson がある場合: `selectedLessonID` を初期化し、Picker の代わりに
     固定表示行（`クラス名 / レッスン名`）を表示して変更不可にする
3. **`WordsView`** (`Sources/Views/WordsView.swift`)
   - `pendingWord` と同様に `router.pendingAddWordLesson` を onAppear / onChange で消費し、
     `WordAddView(fixedLesson:)` をシート表示する
4. **`LessonsView`** (`Sources/Views/LessonsView.swift`)
   - `wordsSection` に「Add Word」ボタンを追加し `router.showAddWord(for: lesson)` を呼ぶ

## 影響範囲

- 上記4ファイルのみ。データモデル・backend への変更なし
- 既存の Words タブからの通常追加（Lesson 選択可）は挙動を変えない

## テスト方針

- `xcodebuild build` でコンパイル確認
- シミュレータで、Lessonページ → Add Word → Wordsタブの追加画面が開き
  Lesson が固定表示・変更不可であること、追加後にその Lesson の Words に反映されることを確認
