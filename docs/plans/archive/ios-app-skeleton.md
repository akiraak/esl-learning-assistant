# iPhoneアプリ スケルトン作成プラン

## 目的・背景

[docs/specs/app-spec.md](../specs/app-spec.md) で定義した ESL Learning Assistant の iOS アプリ（ネイティブ
Swift / SwiftUI）の実装に着手する前段階として、ビルド可能な最小構成のアプリスケルトンを作成する。
Phase 1（撮影 → OCR・翻訳）以降の実装はこのスケルトンの上に追加していく。

## 対応方針

- ディレクトリ: プロジェクト直下に `ios/` を新設し、iOS アプリ一式を格納する
- プロジェクト生成: `xcodegen`（ローカルに導入済み, v2.45.4）を使い `project.yml` から `.xcodeproj` を生成する
  方式を採る。`.xcodeproj` 自体は `.gitignore` 対象とし、`project.yml` をソースとして管理する
  （pbxproj の手書き・コンフリクトを避けるため）
- UI フレームワーク: SwiftUI、最小デプロイターゲットは iOS 17
- アプリ構成（仕様書 4章のデータ管理単位を踏まえた将来の画面構成を見越した最小スケルトン）
  - `ESLLearningAssistantApp.swift`: エントリポイント（`@main`）
  - `ContentView.swift`: タブ構成のルート（撮影 / 単語帳 / 問題 / 設定 の4タブをプレースホルダーで用意）
  - 各タブは中身が空のプレースホルダー View とし、Phase 1 着手時に置き換える
- テスト: `ios/ESLLearningAssistantTests`（Unit, XCTest）, `ios/ESLLearningAssistantUITests`（UI, XCTest）の
  空スケルトンを用意する（xcodegen のテンプレートに準拠）
- バックエンド・管理画面（仕様書 5.2章）は対象外。本プランは iOS アプリのスケルトンのみを扱う

## 影響範囲

- 新規ディレクトリ `ios/` 以下のみ。既存ファイルへの変更は `TODO.md` / `DONE.md` の更新と
  ルート `.gitignore` への iOS 関連エントリ追記のみ

## テスト方針

- `xcodegen generate` でプロジェクト生成が成功すること
- `xcodebuild -scheme ESLLearningAssistant -destination 'platform=iOS Simulator,name=iPhone 17' build`
  でビルドが通ること
- シミュレータ起動 → アプリ起動 → 4タブが表示されタップ切り替えできることを目視確認する
