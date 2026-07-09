# コンテンツタブ（Audio / Documents / 画像 / YouTube の統合）

## 目的・背景

- タブが6個（Lessons / Words / Writing / Audio / Documents / Settings）あるため、iPhone では
  5個目以降の Documents / Settings が iOS 標準の「More」タブ配下に入る。
- More は UIKit のナビゲーションコントローラで画面をラップするため、`NavigationStack` を持つ
  Documents / Settings では **ナビゲーションバーが二重になり、戻るボタン "<" が縦に2個並ぶ**
  （シミュレータで再現確認済み。詳細画面で More の "<" と NavigationStack の "<" が両方表示される）。
- SwiftUI には More 配下の二重ナビバーを解消する公式手段がなく、タブを5個以下にするのが正攻法。
- TODO.md に既存項目「コンテンツタブ（画像 / Audio / YouTube）」があり、ここに Documents も
  統合することで、タブ削減とコンテンツ集約を同時に実現する。

## 対応方針

タブ構成を以下の5個にする（More タブ消滅）:

```
Lessons / Words / Writing / Content / Settings
```

Content タブは画面上部のセグメント（Segmented Picker）でコンテンツ種別を切り替える。
「+」（取り込み）ボタンは選択中の種別に応じたものを表示する。

- セグメント構成（最終形）: Photos | Audio | YouTube | Docs
- Audio / Documents は独立ライブラリ（レッスン紐付けは任意・多対多）で既存ビューを流用可能。
- 画像 / YouTube はレッスン必須の to-one 紐付けのため、横断一覧ビューの新規作成が必要
  （Phase 2 以降で対応）。

## Phase 分割

- **Phase 1: Audio + Documents を Content タブに統合（タブ5個化・今回のバグ解消）**
  - `AppTab` から `.audio` / `.documents` を削除し `.content` を追加
  - `ContentTabView` を新設: `NavigationStack` + セグメント（Audio | Documents）+ 各一覧
  - `AudioView` → `AudioLibraryView` にリネームし、`NavigationStack` / `navigationTitle` を外して
    埋め込み可能にする。`TTSPlaybackService` は push 中の再生継続のため `ContentTabView` が保持し、
    タブ離脱（onDisappear）とセグメント切替（onChange）で停止する
  - `DocumentsView` → `DocumentLibraryView` に同様のリネーム・埋め込み化
  - ルート `ContentView` のタブを5個に変更
- **Phase 2: 画像の横断一覧**（全レッスンの Photo を集約する一覧ビューを新設、セグメントに Photos 追加）
  - `PhotoLibraryView` を新設: `@Query` で全 Photo を撮影日降順に一覧（Audio / Documents と同じ
    埋め込み型ライブラリ。行タップで `PhotoDetailView` へ push、スワイプで確認付き削除）
  - 行は `LessonsView` の `PhotoRow` を共用化して移設（`showsLesson` でレッスン名サブタイトルを
    追加表示。他ライブラリ行に合わせ開示シェブロンも付ける）
  - Photo はレッスン必須（to-one）のため、「+」は `CaptureView` を拡張して対応:
    固定レッスン無しで開いた場合はシート内の Picker でレッスンを選ぶ（既定は最新レッスン、
    レッスンが無ければ案内を表示して撮影ボタンを出さない）。`onCaptured` は追加先レッスンを返し、
    呼び出し元（PhotoLibraryView）が OCR/翻訳をバックグラウンド実行する（LessonsView と同じ方式）
  - セグメント構成は Photos | Audio | Documents（Photos を先頭・既定に）
- **Phase 3: YouTube の横断一覧**（同様に YouTubeLink 集約、セグメントに YouTube 追加）

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Support/AppRouter.swift`（AppTab enum）
- `ios/ESLLearningAssistant/Sources/ContentView.swift`（タブ構成）
- `ios/ESLLearningAssistant/Sources/Views/AudioView.swift` → `AudioLibraryView.swift`
- `ios/ESLLearningAssistant/Sources/Views/DocumentsView.swift` → `DocumentLibraryView.swift`
  （`DocumentRow` は `LessonsView` と共用のため名前は維持）
- 新規: `ios/ESLLearningAssistant/Sources/Views/ContentTabView.swift`
- UIテスト:
  - `ESLLearningAssistantUITests.swift`（タブ構成の検証: Audio/More → Content/Settings）
  - `LessonDocumentAddUITests.swift`（Documents タブ → Content タブ + Documents セグメント）
- XcodeGen 管理のため新規ファイル追加後に `xcodegen generate` が必要

## テスト方針

- シミュレータで実機動作確認: タブが5個になり More が消えること、Content タブの
  セグメント切替（Audio / Documents）、ドキュメント詳細で戻るボタンが1個になること
- 影響する UI テスト（ESLLearningAssistantUITests / LessonDocumentAddUITests）を修正して実行
- 単体テストはビュー構造に依存しないため既存のまま（回帰確認としてビルド＋実行）
