# レッスン画面からの単語詳細表示後にレッスン画面へ戻る

## 目的・背景

レッスン画面（Lessonsタブ）の Words の行をタップすると、`AppRouter.showWord(_:)` が
Wordsタブへ切り替えたうえで `WordDetailView` をプッシュしている。
そのため詳細画面から戻ると Words タブの一覧に戻ってしまい、元のレッスン画面に戻れない。

単語追加フロー（[lesson-word-add-return-to-lesson](archive/lesson-word-add-return-to-lesson.md)）と
同じ「タブ切り替え型」遷移の残りを解消する。

## 対応方針

タブ切り替えをやめ、レッスン画面の NavigationStack に `WordDetailView` を直接プッシュする。
戻る（Back）や削除後の `dismiss()` は自然にレッスン画面へ pop する。

1. `LessonsView`: `@State var selectedWord: Word?` と
   `.navigationDestination(item: $selectedWord)` を追加し、行タップで
   `router.showWord(word)` の代わりに `selectedWord = word` を設定する。
   これで `router` 参照が無くなるため `@Environment(AppRouter.self)` も削除する。
2. `AppRouter`: 不要になった `pendingWord` / `showWord(_:)` を削除。
   タブ選択（`selectedTab`）の保持のみ残し、doc コメントを更新する。
3. `WordsView`: 不要になった `pushedWord` / `consumePendingWord()` と関連する
   `onAppear` / `onChange` / `navigationDestination(item:)` を削除。
   `@Environment(AppRouter.self)` も不要になるため削除する。
   （Wordsタブ内の一覧 → 詳細は従来どおり `NavigationLink`）

## 影響範囲

- `ios/.../Sources/Views/LessonsView.swift`
- `ios/.../Sources/Support/AppRouter.swift`
- `ios/.../Sources/Views/WordsView.swift`
- UIテスト
  - `ESLLearningAssistantUITests.swift`（testAddAndSearchWords）:
    「レッスンの単語タップ → Wordsタブに切り替わる」の assert を
    「Lessonsタブに留まり、戻るとレッスンに戻る」に変更。
    後続の検索ステップの前に明示的な Words タブ切り替えを追加
  - `WordDetailButtonsUITests.swift`: 詳細はレッスン画面上で開く。
    Back でレッスンに戻る確認を追加し、削除後は「レッスンに戻り Words (0)」→
    Wordsタブでも消えている、の順に検証を変更

## テスト方針

- シミュレータでビルドが通ることを確認する
- 影響する UI テスト（ESLLearningAssistantUITests / WordDetailButtonsUITests）に加え、
  周辺の LessonWordAdd / LessonWordRemove も実行してグリーンであることを確認する
