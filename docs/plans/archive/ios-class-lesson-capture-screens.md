# iOS画面実装プラン: クラス追加・レッスン追加・撮影→OCR・翻訳

## 目的・背景

[docs/specs/screen-design.md](../specs/screen-design.md) で検討した画面のうち、まず以下3つの
日常フローをiOSアプリ（[ios/](../../ios/)、現状はタブのみのスケルトン）に実装する。

1. クラスの追加
2. レッスン追加
3. 撮影してOCRと翻訳

[docs/specs/data-model.md](../specs/data-model.md) のスキーマのうち、本タスクで必要な
`Class` / `Lesson` / `Photo` のみを実装する（`Word` / `WordOccurrence` / `Question` /
`QuizResult` は仕様書7章のPhase 2・3で追加する）。

## 対応方針

- **データモデル（SwiftData）**: `Class` / `Lesson` / `Photo` を data-model.md 2〜4章のスキーマ
  通りに実装する。`Lesson.wordOccurrences` / `Lesson.questions` は対象エンティティ未実装のため
  今は追加しない（Phase 2・3で型を追加する際に拡張する）
  - `ESLLearningAssistantApp.swift` に `.modelContainer(for: [Class.self, Lesson.self, Photo.self])`
    を設定する
- **画面構成**: `ContentView` のタブを screen-design.md 0章の通り「ホーム / 単語帳 / 問題 / 設定」
  に変更する（「撮影」タブを廃止し「ホーム」に統合）。単語帳・問題タブは既存のPhase 2/3
  プレースホルダーのまま変更しない
  - `HomeView`（新規、screen-design.md 2.1 の必要部分のみ）: 現在のクラス/レッスンのヘッダー、
    `[+ 新しいレッスン]`、`[📷 写真を追加]`、写真サムネイル一覧。単語帳・問題のサマリ表示は
    対象エンティティ未実装のため今回は含めない
  - `ClassLessonSwitcherView`（新規、screen-design.md 2.2）: クラス一覧とネストしたレッスン一覧、
    クラスごとの `[+]` でレッスン追加、末尾の `[+ クラスを追加]` でクラス追加
  - `CaptureView`（既存プレースホルダーを置き換え、screen-design.md 2.3）: シミュレータでも
    テストできるよう `PhotosPicker`（写真ライブラリ選択）を主手段とし、実機でカメラが使える
    場合は `UIImagePickerController(sourceType: .camera)` も選べるようにする
  - `PhotoDetailView`（新規、screen-design.md 2.5）: 撮影画像・OCR結果・翻訳結果を並べて表示。
    OCRテキストのタップでの単語登録は `Word` 未実装のため対象外
  - 「現在のクラス／レッスン」は `@AppStorage` で直近のIDを保持する端末内UI状態とする
    （データモデルへのフィールド追加はしない。screen-design.md 0章の方針通り）
- **OCR・翻訳**: バックエンド（仕様書5.2章、Claude API中継）は本リポジトリに未実装のため、
  `OCRTranslationService` プロトコルと `MockOCRTranslationService`（固定テキストを返す、
  `processingStatus` を pending→processing→completedと遷移）で代替する。実バックエンド連携は
  別タスクとして `TODO.md` に積み残す
- **画像保存**: `Documents/Photos/` にJPEGとして保存し、`Photo.imageFileName` にはファイル名の
  みを保持する（data-model.md の方針通り、SwiftDataにData blobは持たせない）
- **Info.plist**: 実機カメラ利用のため `NSCameraUsageDescription` を追加する
  （`PhotosPicker` は権限不要のため `NSPhotoLibraryUsageDescription` は不要）

## 影響範囲

- 新規: `ios/.../Sources/Models/{Class,Lesson,Photo}.swift`
- 新規: `ios/.../Sources/Services/OCRTranslationService.swift`
- 新規: `ios/.../Sources/Support/PhotoStorage.swift`
- 新規: `ios/.../Sources/Views/{HomeView,ClassLessonSwitcherView,PhotoDetailView}.swift`
- 変更: `ios/.../Sources/Views/CaptureView.swift`（プレースホルダーから実装に置き換え）
- 変更: `ios/.../Sources/ContentView.swift`（タブ構成）
- 変更: `ios/.../Sources/ESLLearningAssistantApp.swift`（modelContainer追加）
- 変更: `ios/project.yml`（Info.plistにNSCameraUsageDescription追加）
- 変更: `TODO.md` / `DONE.md`

## テスト方針

- `cd ios && xcodegen generate` でプロジェクト生成が成功すること
- `xcodebuild -scheme ESLLearningAssistant -destination 'platform=iOS Simulator,name=...' build`
  でビルドが通ること
- シミュレータで以下を目視確認する（`/run` スキル使用）
  - クラス追加 → レッスン追加 → ホームに反映される
  - 写真追加（PhotosPickerで選択）→ モックOCR・翻訳結果が写真詳細画面に表示される
  - クラス/レッスン切り替えシートから既存レッスンへの切り替えができる

## Phase / Step

- Phase 1: SwiftDataモデル追加（Class / Lesson / Photo）と ModelContainer 設定
- Phase 2: クラス追加・レッスン追加（ホームヘッダー + 切り替えシート）
- Phase 3: 撮影 → OCR・翻訳（撮影画面・写真詳細画面・モックサービス）
- Phase 4: ビルド・シミュレータ動作確認
