# Lesson画面からのコンテンツ追加で Audio が反応しない問題の修正

## 目的・背景

Lesson 画面の Content セクション「＋」→「Add Content」シートで **Audio** 行をタップしても
ファイルピッカーが出ず、何も反応しない。

原因: `AddContentTypeView.swift` で同一 View（NavigationStack 直下）に
`.fileImporter` が2つチェーンされている。

- 98行: Audio 用（`$isShowingAudioImporter`）
- 105行: Document 用（`$isShowingDocumentImporter`）

SwiftUI では同じ View に同種のプレゼンテーション修飾子（`.fileImporter` 等）を
複数付けると後から適用されたものだけが有効になる既知の挙動があり、
Document 側が勝って Audio 側の提示が黙って無視される。
（Content タブの `AudioLibraryView` は View に fileImporter が1つだけなので正常動作。）

## 対応方針

2つの `.fileImporter` を **1つに統合**し、どちらの種別で開いたかを state で持つ。

- `enum FileImporterKind { case audio, document }` と
  `@State private var importerKind: FileImporterKind = .audio` を追加
- Audio 行タップ: `importerKind = .audio; isShowingFileImporter = true`
- Document 行タップ: `importerKind = .document; isShowingFileImporter = true`
- 単一の `.fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: importerKind に応じて切替)` で提示し、
  completion で `importerKind` により `handleAudioImport` / `handleDocumentImport` に振り分ける
- `isShowingAudioImporter` / `isShowingDocumentImporter` は削除

completion 内で binding のリセット順に依存しないよう、種別は
`isPresented` とは独立した `importerKind` に保持する。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/AddContentTypeView.swift` のみ
- Photo / YouTube の `.sheet` 2連チェーンは iOS 14.5+ では複数共存可のため今回触らない
- 取り込み処理本体（`AudioFileImporter` / `DocumentFileImporter`）は変更なし

## テスト方針

1. `xcodegen generate` 不要（ファイル追加なし）。シミュレータ向けビルドが通ることを確認
2. シミュレータで Lesson → ＋ → Audio をタップし、Files ピッカーが提示されることを確認
3. 同経路で Document をタップし、従来どおりピッカーが提示されること（リグレッションなし）を確認
