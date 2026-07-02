# レッスン画面からの単語追加後にレッスン画面へ戻る

## 目的・背景

現状、レッスン画面（Lessonsタブ）の Words セクションの「+」ボタンは
`AppRouter.showAddWord(for:)` を呼び、**Wordsタブへ切り替えたうえで**単語追加シートを開いている。
そのためシートを閉じる（追加・キャンセルいずれも）と Words タブに残ってしまい、
元のレッスン画面に戻れない。

TODO: 「レッスン画面で単語を追加した場合は戻るときはレッスンに戻る」

## 対応方針

タブ切り替えをやめ、レッスン画面上で直接 `WordAddView(fixedLesson:)` をシート表示する。
シートを閉じれば自然に Lessons タブのレッスン画面に戻る。

1. `LessonsView`: `@State var wordAddLesson: Lesson?` を追加し、`.sheet(item:)` で
   `WordAddView(fixedLesson:)` を表示。追加ボタンは `router.showAddWord` の代わりに
   `wordAddLesson = lesson` を設定する。
2. `AppRouter`: 不要になった `pendingAddWordLesson` / `showAddWord(for:)` を削除。
3. `WordsView`: 不要になった `fixedLessonForAdd` / `consumePendingAddWordLesson()` と
   関連する `onAppear` / `onChange` を削除。シートは常に `WordAddView()`（レッスン固定なし）。

※ レッスン画面の単語タップ → Words タブで詳細表示（`showWord`）は仕様どおり維持する。

## 影響範囲

- `ios/.../Sources/Views/LessonsView.swift`
- `ios/.../Sources/Support/AppRouter.swift`
- `ios/.../Sources/Views/WordsView.swift`
- UIテスト
  - `LessonWordAddUITests.swift`: 「Wordsタブに切り替わる」前提の assert を
    「Lessonsタブに留まり、レッスンのWordsに即反映される」に変更
  - `LessonWordRemoveUITests.swift`: 追加後に Words タブへ切り替わる前提の箇所に
    明示的なタブ切り替えを追加
  - `WordDetailButtonsUITests.swift`: 追加後に単語タップで詳細を開く流れ。
    単語タップは `showWord` で Words タブへ遷移するため変更不要の見込み（要確認）

## テスト方針

- シミュレータでビルドが通ることを確認する
- 影響する UI テスト（LessonWordAdd / LessonWordRemove / WordDetailButtons）を実行して
  グリーンであることを確認する
