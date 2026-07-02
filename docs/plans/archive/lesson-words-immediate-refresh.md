# レッスン画面で単語追加直後にWordsセクションへ即時反映されない問題の修正

## 目的・背景

レッスン画面（LessonsView）の Words セクションから単語を追加すると、シートを閉じた直後は
一覧に表示されず、しばらくして（別の保存イベントが走ったタイミングで）表示される。

原因: `WordAddView.addWord()` は `WordOccurrence(word:lesson:)` を to-one 側
（`occurrence.lesson`）だけ設定して `modelContext.insert` しており、逆側の
`lesson.wordOccurrences` 配列への反映と Observation の変更通知が次の autosave まで遅れる。
レッスン画面は `lesson.wordOccurrences` を読んで表示しているため、シートが閉じて body が
再評価されても古い配列のままになる。

## 対応方針

`WordAddView.addWord()` で出現記録を作るとき、insert に加えて **lesson 側の配列にも明示的に
append** する（`lesson.wordOccurrences.append(occurrence)`）。lesson 側プロパティを直接変更
することで、`lesson.wordOccurrences` を読んでいるレッスン画面の Observation が即時に発火する。
関係の実体は同一なので二重登録にはならない（表示側も word.id で重複除去済み）。

あわせて追加完了時に明示的な `modelContext.save()` を行う
（autosave 任せだと直後の強制終了で失われる既知パターン。メモ機能・単語削除と同じ方針）。

## 影響範囲

- iOS: `Sources/Views/WordAddView.swift` のみ（レッスン固定追加と Words タブからの
  レッスン選択追加の両経路に効く）

## テスト方針

- `xcodebuild` ビルド確認
- 既存UIテスト `LessonWordAddUITests`（追加直後にレッスン画面の Words に出ることを検証）と
  `LessonWordRemoveUITests` が通ること
