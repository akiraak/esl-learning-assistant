# iOS: OCR結果・翻訳結果の表示を swift-markdown-ui に置き換える

## 目的・背景

[ios-markdown-block-rendering.md](archive/ios-markdown-block-rendering.md) で
`PresentationIntent` を使った自前のブロック単位Markdown表示（`MarkdownContentView`）を実装したが、
テーブル・コードブロックのシンタックスハイライト・画像など今後Markdownの記法が広がった場合に
自前実装では追従コストが高い。汎用パッケージを使えないか確認したところ利用可能だったため、
`swift-markdown-ui`（https://github.com/gonzalezreal/swift-markdown-ui）に切り替える。

## 対応方針

### Step 1: SPM依存として `swift-markdown-ui` を追加する

- Xcodeプロジェクト（`.pbxproj`、gitignore対象）に `XCRemoteSwiftPackageReference` /
  `XCSwiftPackageProductDependency`（`MarkdownUI`）を追加し、アプリターゲットの
  `packageProductDependencies` ・ Frameworksビルドフェーズに組み込む
  （バージョンは `2.4.1` 以降を許容する `upToNextMajorVersion`）

### Step 2: `PhotoDetailView.swift` を `Markdown(_:)` ビューに置き換える

- OCR結果・翻訳結果の表示を自前の `MarkdownContentView` から `MarkdownUI` の `Markdown(String)` に置き換える
- 不要になった `MarkdownContentView.swift` を削除する

## 影響範囲

- `ios/ESLLearningAssistant.xcodeproj/project.pbxproj`（gitignore対象、ローカルのみ反映）
- `ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`
- `ios/ESLLearningAssistant/Sources/Views/MarkdownContentView.swift`（削除）

## テスト方針

- `xcodebuild -resolvePackageDependencies` でパッケージ解決を確認
- `xcodebuild -scheme ESLLearningAssistant -destination 'generic/platform=iOS Simulator' build` でビルド確認
