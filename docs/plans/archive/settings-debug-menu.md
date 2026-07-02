# 設定タブ: デバッグメニュー（データ削除機能）

## 目的・背景

開発中はテストデータ（クラス・レッスン・写真・単語）が溜まりやすく、動作確認のたびに
アプリを削除して再インストールするのは手間がかかる。設定タブにデバッグメニューを追加し、
アプリ内からデータを一括削除できるようにする。

提供する操作は以下の 3 つ。

- **データの全クリア**: SwiftData の全エンティティ（Class / Lesson / Photo / Word /
  WordOccurrence）と保存済み写真ファイルを削除する。設定値（サーバー URL・TTS 設定などの
  UserDefaults）は開発時に消えると不便なので対象外とする
- **クラスとそのレッスンの全削除**: 全 Class を削除する。cascade で Lesson → Photo /
  WordOccurrence も削除される。Word 本体は残す（単語帳は維持される）
- **単語の全削除**: 全 Word を削除する。cascade で WordOccurrence も削除される。
  クラス・レッスン・写真は残す

デバッグメニューは `#if DEBUG` で囲み、Debug ビルドのみ表示する（Release ビルドには
コード自体を含めない）。

## 対応方針

### Step 1: PhotoStorage に削除ヘルパーを追加

- `PhotoStorage.delete(fileName:)`: 指定ファイルを削除する
- `PhotoStorage.deleteAll()`: `Documents/Photos` ディレクトリごと削除する
- SwiftData の cascade 削除では画像ファイルは消えないため、Photo エンティティ削除時に
  合わせて呼び出す

### Step 2: データ削除ロジックの実装

- `Sources/Support/DebugDataCleaner.swift` を新設し、`ModelContext` を受け取る静的メソッドで
  3 操作を実装する
  - `deleteAllData(context:)`: 全 Class・全 Word を削除 → `PhotoStorage.deleteAll()`
  - `deleteAllClasses(context:)`: 全 Class を削除 → `PhotoStorage.deleteAll()`
    （全 Photo は必ずいずれかの Lesson 配下にあるため、ディレクトリごと削除でよい）
  - `deleteAllWords(context:)`: 全 Word を削除
- 削除は `FetchDescriptor` で全件フェッチして 1 件ずつ `context.delete(_:)` する。
  バッチ削除（`context.delete(model:)`）は cascade ルールが適用されない既知の問題が
  あるため使わない
- 削除後に `try context.save()` して確定する

### Step 3: SettingsView にデバッグセクションを追加

- `#if DEBUG` で囲んだ `Section("デバッグ")` を Form 末尾に追加する
- 3 つの削除ボタンを `role: .destructive`（赤字）で配置する
- 誤操作防止のため、各ボタンは `confirmationDialog` で確認してから実行する
  （削除内容と「元に戻せない」旨を明記する）
- 実行後は現在のデータ件数が変わったことがわかるよう、セクション footer に
  件数表示（クラス数・レッスン数・写真数・単語数）を出す（`@Query` の count を利用）

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Support/PhotoStorage.swift`（削除ヘルパー追加）
- 新規: `ios/ESLLearningAssistant/Sources/Support/DebugDataCleaner.swift`
- `ios/ESLLearningAssistant/Sources/Views/SettingsView.swift`（デバッグセクション追加）

## テスト方針

- `xcodebuild` でシミュレータ向け Debug ビルドが通ることを確認する
- ユニットテスト: in-memory の `ModelContainer` を使い、以下を検証する
  - `deleteAllData` 後に全エンティティが 0 件になる
  - `deleteAllClasses` 後に Class / Lesson / Photo / WordOccurrence が 0 件、Word は残る
  - `deleteAllWords` 後に Word / WordOccurrence が 0 件、Class / Lesson / Photo は残る
- シミュレータで手動確認: データ投入 → 各削除操作 → 該当タブで消えていること、
  確認ダイアログのキャンセルで削除されないことを確認する
- Release 構成でデバッグセクションが表示されない（コンパイルされない）ことを確認する
