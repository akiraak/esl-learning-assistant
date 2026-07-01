# 撮影済み（未翻訳）写真の翻訳機能

## 目的・背景

`CaptureView` は撮影直後にその場で `OCRTranslationService.process` を呼ぶため新規撮影分は自動で
OCR・翻訳される。一方、OCR・翻訳機能を実装する前に撮影された写真や、途中でアプリが終了して
処理が中断した写真は `processingStatus` が `.pending` / `.processing` のまま残り、
`PhotoDetailView` はその状態でスピナー表示するだけで実際に処理を呼び出すコードが無いため、
永久に「処理中」のまま翻訳されない。

この状態の写真に対して、(1) 詳細画面を開いた際に自動で翻訳を開始する、(2) レッスン単位で
未翻訳の写真をまとめて翻訳できるボタンを追加する、の2点で対応する。

## 対応方針

### Step 1: PhotoDetailView で pending/processing 状態を実際に処理する

- `.pending` の写真は詳細画面表示時（`.task`）に自動で `ocrTranslationService.process` を呼ぶ。
- `.processing` のまま残っている写真（アプリ強制終了などで中断）は自動再開せず、
  `.failed` と同様に手動再試行ボタンを出す（サーバに投げっぱなしのリクエストが実在するか
  不明なため自動リトライは避ける）。
- 二重実行防止のため既存の `isRetrying` 相当のフラグで処理中はボタン操作不可にする。

### Step 2: HomeView にレッスン単位の一括翻訳ボタンを追加

- レッスンの写真一覧セクションに、`.pending`/`.failed` の写真が1件以上ある場合のみ
  「未翻訳の写真をまとめて翻訳」ボタンを表示。
- タップで対象写真を順番に（同時実行せず逐次）`process` し、進捗（何件中何件処理済みか）を表示する。
- 処理中は他の操作（新規撮影・レッスン追加ボタン等）を無効化しない（写真一覧の読み取りのみのため）。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`
- `ios/ESLLearningAssistant/Sources/Views/HomeView.swift`

新規モデル変更・バックエンド変更は無し（既存の `RemoteOCRTranslationService` をそのまま利用）。

## テスト方針

- Xcode ビルドが通ることを `xcodebuild -scheme ESLLearningAssistant build` で確認する
  （シミュレータ/実機での実地確認は今回のセッションでは行わない）。
