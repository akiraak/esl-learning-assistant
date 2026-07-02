# TODO

- [ ] ESLアプリ実装 [spec](docs/specs/app-spec.md)
  - [ ] Phase 3: 問題作成
  - [ ] シミュレータ/実機のGUI操作で撮影→OCR・翻訳フルフロー（クラス/レッスン作成→撮影→
        結果表示→失敗時の再試行）を動作確認する（ANTHROPIC_API_KEYは設定済みで、backend側の
        `/api/ocr-translate`実キー呼び出しはcurlで複数回成功確認済み。iOS側のGUI操作は
        シミュレータ/実機操作権限が無いこのセッションでは未確認）
  - [ ] Lessonページの Wordsに単語追加ボタン。タップでWordsタブの追加画面に遷移させLessonは設定されて変更できない状態にする
  - [ ] Lessonページの Add photo を Contentの中に置く

- [ ] 管理画面のログ時間をシアトルのタイムゾーンにする
- [ ] クラス名・レッスン名編集の保存も明示的に `modelContext.save()` する（メモ機能の検証で、
      autosave任せだと保存直後にアプリを強制終了された場合に変更が失われることを確認済み。
      `LessonEditView` / `ClassEditView` / 各Add系ビューも同じパターンの可能性がある）

## デバックメニュー(On Setting)
  - 単語のAI生成物を全て削除