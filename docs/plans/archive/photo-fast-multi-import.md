# レッスンへの写真コンテンツ追加を素早く複数枚

## 目的・背景

textbook のページ写真をレッスンへ追加する現状フローは「1 枚ずつ・OCR/翻訳の完了を待ってから閉じる」同期処理で、複数ページを取り込むときに待ち時間が積み上がる。素早く複数枚まとめて追加できるようにする。狙いは 2 点:

1. **OCR/翻訳を非同期にして、追加直後にアプリへ操作を戻す** — 写真を保存したら即座に Capture シートを閉じ、OCR/翻訳はバックグラウンドで進める。
2. **写真追加時に複数選択** — ライブラリから複数枚をまとめて選び、一括で pending として登録する。

## 現状整理（調査結果）

- **ピッカー**: `Sources/Views/CaptureView.swift`
  - カメラ（`CameraPicker`, 単一）と `PhotosPicker`（`selection: PhotosPickerItem?` = **単一選択**）。
  - `handleCapturedImage`（78–89 行）: `PhotoStorage.save` → `Photo(.pending)` を insert/save → **`await ocrTranslationService.process(photo)` の完了を待つ** → `isProcessing` で UI をブロック → 完了後に `onCaptured(photo)` + `dismiss()`。
- **呼び出し元**: `CaptureView` は `LessonsView.swift:57-63` の `.sheet` のみ。`onCaptured` で受けた photo を `selectedPhoto` にセットし `.navigationDestination`（67–69 行）で `PhotoDetailView` へ自動遷移。
- **OCR/翻訳サービス**: `OCRTranslationService`（`@MainActor`）／実装 `RemoteOCRTranslationService`。バックエンド `api/ocr-translate`（Anthropic Claude）へ画像を投げ、OCR と翻訳を 1 レスポンスで受け取る。処理は非同期（`async`）で、内部で `Photo.processingStatus` を `.processing`→`.completed`/`.failed` に更新し、結果を `Photo.ocrText`/`translatedText`/`translationLanguage` に格納する。
- **既存の非同期基盤（再利用できる）**:
  - `Photo.processingStatus`（pending/processing/completed/failed）と行の `PhotoRow.statusLabel` で進捗表示済み。
  - `LessonsView.translateAllPending(in:)`（419–430 行）が pending/failed の photo を順次 `process` する。`untranslatedCount > 0` のとき「Translate Untranslated Photos」ボタン（169–183 行）が出て、失敗時の再試行手段も既にある。
  - `PhotoDetailView` にも個別再試行の `process` あり。
- **SwiftData モデル変更は不要**（既存プロパティ・ステータスで足りる）。

## 対応方針

処理の起点を「破棄される `CaptureView`」から「画面に残り続ける `LessonsView`」へ移し、追加は pending 登録だけにして即 dismiss、OCR/翻訳は `LessonsView` 所有のサービスでバックグラウンド実行する。既存 `translateAllPending` をそのまま自動起動の実体として再利用する。

### Phase 1: OCR/翻訳を非同期化して即座にアプリへ戻す

- `CaptureView.handleCapturedImage` から `await ocrTranslationService.process(photo)` の呼び出しを削除。`PhotoStorage.save` → `Photo(.pending)` insert/save → コールバック → `dismiss()` までを一瞬で終える。
- `isProcessing` ブロッキング UI（`ProgressView("Processing OCR & translation…")` / `.disabled(isProcessing)`）は保存が一瞬になるため撤去、もしくは保存中のみの軽量表示に縮小。
- `CaptureView` 内の `ocrTranslationService` インスタンス（16 行）は不要になるので削除。処理は `LessonsView` 側の既存インスタンスに一本化。
- `onCaptured` コールバックを見直す:
  - 現状 `(Photo) -> Void` + 自動で `PhotoDetailView` 遷移。非同期化すると遷移直後の詳細は中身が空（pending）になるため、**追加後は詳細へ自動遷移せずレッスン画面に留まる**方針に変更（行の status ラベルで進捗が見える。詳細は行タップで開く）。
  - コールバックは「追加完了の通知」に簡素化（`() -> Void`）。`LessonsView` はこれを受けて `Task { await translateAllPending(in: lesson) }` を起動し、pending を順次処理する。
  - これに伴い `selectedPhoto` の自動遷移用途（60 行の代入）を廃止。`selectedPhoto`/`.navigationDestination` 自体は行タップ遷移で引き続き使用。
- バックグラウンド処理は `LessonsView`（永続）所有の `ocrTranslationService` と `Task` で実行するため、`CaptureView` が破棄されても継続する。
- 失敗時は既存の `failed` ステータス＋「Translate Untranslated Photos」ボタンで再試行できる（追加実装不要）。

### Phase 2: 写真追加時に複数選択

- `CaptureView` の `PhotosPicker` を複数選択へ変更:
  - `@State private var photosPickerItems: [PhotosPickerItem] = []`、`PhotosPicker(selection: $photosPickerItems, maxSelectionCount: <上限 or 無指定>, matching: .images)`。
  - `.onChange(of: photosPickerItems)` で配列を順に `loadTransferable` → `PhotoStorage.save` → `Photo(.pending)` insert。全件保存後に `saveOrLog` → コールバック → `dismiss()`。
- カメラ経由は 1 枚ずつ（従来どおり）。複数選択はライブラリ選択に適用。
- 保存はメインで一瞬。OCR/翻訳は Phase 1 のバックグラウンド処理（`translateAllPending`）が pending 全件を順次さばく。
  - 実行方式は当面 **逐次**（`translateAllPending` の for ループ準拠）。多数枚での体感が悪ければ小さめの並列度（2–3）を検討（バックエンド負荷とレート次第、別 TODO 化可）。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/CaptureView.swift`（主。ピッカー複数化・同期処理撤去・コールバック簡素化）
- `ios/ESLLearningAssistant/Sources/Views/LessonsView.swift`（`onCaptured` 受け口の変更、追加後の自動遷移廃止、追加直後のバックグラウンド処理起動）
- モデル・バックエンド・`PhotoDetailView` は変更なし（既存の status/`process`/再試行をそのまま活用）
- SwiftData マイグレーション不要

## テスト方針

- **手動（実機/シミュレータ, `/run`）**:
  - 単一追加: 写真 1 枚追加 → 即レッスン画面に戻る → 行が pending→processing→completed に遷移。
  - 複数追加: ライブラリから複数枚選択 → 即戻る → 全件 pending 登録 → 順次 completed。
  - 失敗系: ネットワーク不通などで failed → 「Translate Untranslated Photos」で再試行できる。
  - カメラ: 従来どおり 1 枚追加できる。
  - 詳細遷移: 追加後は自動遷移せず、行タップで `PhotoDetailView` が開く。
- **ビルド**: `xcodegen generate` 後にビルド（プロジェクトは XcodeGen 管理、pbxproj は生成物）。
- 既存の一括翻訳・個別再試行フローに regression がないこと。
