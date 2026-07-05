# 音声タブ + Dropbox 連携 実装（案A: アプリに SwiftyDropbox SDK）

調査 → [audio-tab-dropbox-integration.md](audio-tab-dropbox-integration.md)。
ユーザー決定: **案A（アプリ内 OAuth で直接 Dropbox 連携）**。

## 目的

iOS に「Audio」タブを追加し、**Dropbox（アプリ専用フォルダ）に置いた音声ファイルを
一覧 → 端末に取り込み → 再生**できるようにする。再生・ローカル保存は既存
`TTSPlaybackService` / `TTSAudioStore` の作法を流用する。

## 前提（ユーザー側の手動セットアップ）

SwiftyDropbox は OAuth に **App Key** が必要。これは Dropbox App Console でアプリ登録して得る。
- https://www.dropbox.com/developers/apps で「Create app」
  - API: **Scoped access**
  - Access type: **App folder**（アプリ専用の `Apps/<app名>/` 配下のみに限定）
  - Permissions タブで **`files.metadata.read`** と **`files.content.read`** を有効化
- 発行された **App key** を `ios/project.yml` の `DROPBOX_APP_KEY` に設定
  （URL スキーム `db-<APP_KEY>` はビルド時に Info.plist へ焼き込むため、実行時変更は不可）。
- ユーザーはその App Folder（`Apps/<app名>/`）に音声ファイル（mp3 / m4a / wav / aac）を置く。

App key はシークレットではない（PKCE で保護）ため project.yml にコミット可。既定は空文字。

## Phase 1: プロジェクト設定（依存 & Info.plist）

`ios/project.yml`:
- `packages` に `SwiftyDropbox`（SPM, `https://github.com/dropbox/SwiftyDropbox` from 10.0.0 目安）。
- ターゲット `dependencies` に `package: SwiftyDropbox`。
- `settings.base` に `DROPBOX_APP_KEY: ""`（`BACKEND_API_SECRET` と同じ作法）。
- Info.plist `properties`:
  - `DropboxAppKey: $(DROPBOX_APP_KEY)`（コードから読む）
  - `CFBundleURLTypes`: `CFBundleURLSchemes = ["db-$(DROPBOX_APP_KEY)"]`
  - `LSApplicationQueriesSchemes`: `["dbapi-2", "dbapi-8-emm"]`（Dropbox アプリ検出用）
- `xcodegen generate`（[[ios-xcodegen-project]]）。

`AppSettingsKeys.swift`:
- `defaultAPISecret` と同じ作法で `dropboxAppKey`（Info.plist `DropboxAppKey`）アクセサを追加。

## Phase 2: Dropbox クライアント（OAuth）

`Sources/Services/DropboxService.swift`（`@MainActor @Observable`）:
- `configure()`: App key が非空なら `DropboxClientsManager.setupWithAppKey(key)`。空ならスキップし
  「未設定」状態にする（UI で案内）。App 起動時に呼ぶ。
- `isAuthorized`: `DropboxClientsManager.authorizedClient != nil` を公開。
- `startAuth()`: `ScopeRequest(scopeType: .user, scopes: ["files.metadata.read","files.content.read"],
  includeGrantedScopes: false)` で `authorizeFromControllerV2(...)`。SwiftUI なので
  最前面の `UIViewController`（keyWindow の rootVC）を取得して渡す。`openURL` は
  `UIApplication.shared.open`。
- `handleRedirect(_ url: URL) -> Bool`: `DropboxClientsManager.handleRedirectURL(url,
  includeBackgroundClient: false) { ... }`。完了で `isAuthorized` を更新。
- `unlink()`: `DropboxClientsManager.unlinkClients()`（サインアウト用、任意）。

`ESLLearningAssistantApp.swift`:
- `init()` で `DropboxService.shared.configure()`。
- `WindowGroup` の内容に `.onOpenURL { DropboxService.shared.handleRedirect($0) }`。

## Phase 3: 一覧・ダウンロード

`DropboxService`:
- `struct AudioEntry { let name: String; let pathLower: String; let size: UInt64 }`。
- `listAudioFiles() async throws -> [AudioEntry]`: `client.files.listFolder(path: "")`
  （App Folder ルート）。必要なら `listFolderContinue` でページング。拡張子
  （mp3/m4a/wav/aac/caf/aiff）でフィルタ。サブフォルダ再帰は将来対応（まずルート）。
- `download(pathLower:) async throws -> Data`: `client.files.download(path:)` の
  `.response` を async ラップして `Data` を返す。
- SDK のコールバック API は `withCheckedThrowingContinuation` で async 化する。

`Sources/Services/AudioClipStore.swift`（`TTSAudioStore` を踏襲）:
- `Application Support/audio/` 配下。キーは Dropbox の `pathLower` の sha256 + 元拡張子。
- `localURL(pathLower:) -> URL?` / `save(data:pathLower:) -> URL` / `removeAll()`。

## Phase 4: 音声タブ UI

- `AppRouter.swift`: `AppTab` に `.audio` を追加。
- `ContentView.swift`: `Label("Audio", systemImage: "waveform")` のタブを追加（Writing と
  Settings の間あたり）。
- `Sources/Views/AudioView.swift`:
  - App key 未設定: セットアップ案内（project.yml に App key を、の旨）。
  - 未認証: 「Connect Dropbox」ボタン → `startAuth()`。
  - 認証済み: Dropbox の音声一覧を表示。各行:
    - 未取り込み（`AudioClipStore.localURL == nil`）: ダウンロードボタン →取り込み→保存。
    - 取り込み済み: 再生ボタン（`TTSPlaybackService.play(url:)`）／再生中は停止。
  - Pull-to-refresh で一覧再取得。`onDisappear` で再生停止。
  - エラーは alert 表示（401/ネットワーク等）。

再生バー（`TTSPlayerBar`）を出すかは MVP では任意。まずは行内の再生/停止で最小実装。

## 影響範囲

- 新規: `Services/DropboxService.swift`, `Services/AudioClipStore.swift`, `Views/AudioView.swift`。
- 変更: `ios/project.yml`（依存・設定・Info.plist）, `AppSettingsKeys.swift`,
  `AppRouter.swift`（`AppTab`）, `ContentView.swift`（タブ）, `ESLLearningAssistantApp.swift`
  （configure + onOpenURL）。
- backend 変更なし（案A は端末が直接 Dropbox と通信）。
- SwiftData エンティティは MVP では追加しない（ファイル存在ベースで状態管理。メタ管理が
  必要になったら [[ios-swiftdata-new-entity-checklist]] に従って追加）。

## テスト方針

- `xcodegen generate` 後 `xcodebuild` でビルド確認。
- 手動（実機、要 App key 設定）:
  - App key 未設定時は案内が出る。
  - Connect → Dropbox 認証 → アプリに戻り認証済みになる。
  - App Folder に置いた音声が一覧に出る → ダウンロード → 再生できる。
  - 画面再訪で取り込み済み状態が維持される。
  - 実音声の確認・App key 発行はユーザーに依頼。

## Phase 分割（TODO 子タスク）

- [ ] Phase 1: project.yml 依存・Info.plist・xcodegen
- [ ] Phase 2: DropboxService（OAuth）+ App 統合
- [ ] Phase 3: 一覧・ダウンロード + AudioClipStore
- [ ] Phase 4: AudioView + タブ追加
- [ ] Phase 5: ビルド確認・ユーザー手動テスト依頼
