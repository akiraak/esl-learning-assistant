# UIテスト testClassLessonCaptureFlow の現行環境対応

## 目的・背景

`ESLLearningAssistantUITests.testClassLessonCaptureFlow` が iOS 26 環境で失敗し続けている（レッスンカレンダー化以前からの既存問題）。原因は2点。

1. **PHPicker の確定操作の変更**: iOS 26 の PHPicker は複数選択の確定がナビバーの「追加/Add」ボタンではなく右上の ✓ ボタンに変更された。テストは `app.navigationBars.buttons["追加"/"Add"]` を待つため確定できない。
2. **写真追加後のフロー変更**: 現行フローは写真追加後に写真詳細へ自動遷移しない（`LessonsView` はレッスン画面に留まり、OCR/翻訳をバックグラウンド実行する）。テスト末尾の `OCR Result (English)` 見出し検証は `PhotoDetailView`（completed 状態）でしか成立しないため、コンテンツ一覧の写真行をタップして詳細を開く手順が必要。

## 対応方針

- **Phase 1: PHPicker 確定ボタンの実体調査**
  - テストを picker 表示段階まで実行し、スクリーンショットと accessibility ツリー（`app.debugDescription`）から ✓ ボタンの識別子/ラベルを特定する
  - PHPicker はプロセス外ホストのため要素が取れない可能性あり。その場合は既存の写真セルタップと同様に座標タップへフォールバックする
- **Phase 2: テスト修正**（`ios/ESLLearningAssistantUITests/ESLLearningAssistantUITests.swift`）
  - 確定操作を iOS 26 の ✓ ボタンに対応させる（旧「追加/Add」も許容して後方互換に）
  - 確定後はレッスン画面へ戻る想定に変更: コンテンツ一覧に写真行が出るのを待つ → 写真行をタップ → `PhotoDetailView` で `OCR Result (English)` を検証
  - OCR はバックグラウンドで実バックエンド（`/api/ocr-translate`）を呼ぶため、見出し待ちのタイムアウトを実処理に見合う長さ（60s 程度）へ延長
- **Phase 3: 実行・検証**
  - シミュレータで該当テストを単体実行して green を確認する
  - バックエンド疎通（URL / API Secret）が原因で completed に到達しない場合は、検証内容の見直し（E2E 環境変数化 or 状態遷移までの検証）をこのプランに追記して判断する

## 影響範囲

- `ios/ESLLearningAssistantUITests/ESLLearningAssistantUITests.swift` のみ（アプリ本体コードは変更しない想定。写真行の特定に識別子が必要になった場合のみ `PhotoRow` 周辺へ最小限の `accessibilityIdentifier` 追加があり得る）

## テスト方針

- `testClassLessonCaptureFlow` を単体実行して通過を確認する
- アプリコードに識別子を追加した場合は、同ファイル内の他テストと `ContentPhotoLibraryUITests` の通過も確認する
