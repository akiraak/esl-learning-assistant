# 音声タブ + Dropbox 連携（調査）

## 目的・背景

ユーザー要望: **iOS アプリに「音声タブ」を追加し、そこから音声を追加・再生できるようにする**。
音声ソースとして **Dropbox に置いた音声ファイル**を取り込みたい。

まず本タスクでは **「Dropbox とどう連携するのが最適か」を調査**し、実装方式を決める（実装は次フェーズ）。

### 現状の把握（既存コードから）

- iOS: SwiftUI + SwiftData。タブは `ContentView.swift` の `TabView` で 4 つ（Lessons / Words /
  Writing / Settings）。タブ enum は `AppRouter.swift` の `AppTab`。
- 音声再生の既存資産:
  - `TTSPlaybackService`（`AVAudioPlayer` ラッパー。ローカルファイル URL 再生・停止・終了検知）
  - `TTSAudioStore`（`Application Support/tts/` にキャッシュ、`sha256` キー管理）
  - `SpeechService`（端末内蔵 TTS）、`GeminiSpeechService`、`SoundEffectService`
  - → **再生・ローカル保存の仕組みは流用できる。追加すべきは「音声の取り込み元 = Dropbox」の部分。**
- サーバ通信: `BackendAPI`（`X-API-Secret` ヘッダ認証、base URL は Settings 設定）。
  バックエンドは Express（`backend/src/index.ts`）。既存の秘密情報は `backend/.env`
  （`ANTHROPIC_API_KEY` / `GEMINI_API_KEY` / `OPENAI_API_KEY` / `API_SECRET`）に集約。
- 既存の音声保存パターン: `POST /api/tts` がオンデマンド合成 → `backend/data/tts/<hash>.wav`
  にキャッシュ。「事前に用意した音声を外部から取り込む」フローは**未実装**。

## 調査: Dropbox 連携の技術選択肢

Dropbox API v2 を使う。認証は OAuth 2.0（スコープ制。`files.metadata.read` で一覧、
`files.content.read` でダウンロード）。アプリ登録時に **App Folder（アプリ専用フォルダのみ）**
か **Full Dropbox（全体アクセス）** を選ぶ。以下 4 案を比較する。

### 案A: アプリに SwiftyDropbox SDK を組み込む（アプリ内 OAuth）

- 公式 Swift SDK [`dropbox/SwiftyDropbox`](https://github.com/dropbox/SwiftyDropbox) を SPM で追加。
- アプリ内で OAuth（`SFSafariViewController` または Dropbox アプリへ委譲）→ アクセストークン取得。
  `db-<APP_KEY>` の URL スキームを Info.plist に登録する必要あり。
- `filesListFolder` でファイル一覧、`filesDownload` で音声をダウンロード → `TTSAudioStore` 相当の
  ローカル保存 → `TTSPlaybackService` で再生。
- **App Folder スコープ**にすれば「Dropbox の `アプリ/ESLLearningAssistant/` 配下だけ」に限定でき、
  ユーザーはそこに音声を置くだけでよい（安全・分かりやすい）。
- 長所: サーバ改修不要。端末が直接 Dropbox と通信するので構成がシンプル。SDK がトークン更新も担う。
- 短所: iOS に SDK 依存追加。OAuth UI とトークンの Keychain 保存をアプリに実装。
  App Key/Secret をアプリに埋め込む（PKCE 利用でリスク低減可）。

### 案B: バックエンド経由（サーバが Dropbox トークンを保持）

- 開発者（ユーザー本人）が一度だけ OAuth し、**refresh token を `backend/.env` に格納**。
  サーバが Dropbox API を叩き、アプリは既存 `BackendAPI`（`X-API-Secret`）経由で
  `GET /api/audio`（一覧）・`GET /api/audio/:id`（ダウンロード）を呼ぶ。
- 既存の `/api/tts` と同様、`backend/data/audio/` にキャッシュ + DB 管理でき、
  管理画面（`admin.ts`）に音声一覧・試聴も足せる。
- 長所: アプリに Dropbox 依存・OAuth UI 不要。秘密情報がサーバに集約（既存方針と一致）。
  複数端末で同じ音声を共有、キャッシュで Dropbox 呼び出し削減。
- 短所: サーバ改修が必要。**単一 Dropbox アカウント（ユーザー本人）前提**——各エンドユーザーが
  自分の Dropbox を繋ぐ用途には不向き。ただし現状アプリは実質個人利用なので許容範囲。

### 案C: 共有リンク（公開 URL）方式

- Dropbox で音声フォルダ/ファイルの共有リンクを作り、URL からダウンロード
  （`?dl=1` で直接ダウンロード）。OAuth も SDK も不要。
- 長所: 最も実装が軽い。既存の `URLSession` ダウンロード + `TTSAudioStore` 保存だけ。
- 短所: 「アプリから音声を**追加**する」体験にならない（フォルダ一覧を API で取れず、
  URL を手入力 or 事前ハードコードになりがち）。管理が手作業。要望の UX と乖離。

### 案D: Dropbox 連携なし・手動配置（比較用ベースライン）

- Files アプリ / iTunes 共有 / バックエンドへ手動 scp などで音声を配置。
- Dropbox を使う要望から外れるため不採用。比較の下限として記載。

## 比較まとめ

| 観点 | A: アプリ内SDK | B: バックエンド経由 | C: 共有リンク |
|---|---|---|---|
| 「アプリから追加」UX | ◎ フォルダ閲覧・選択 | ◎ サーバ一覧を表示 | △ URL手入力寄り |
| 実装コスト | 中（OAuth UI + SDK） | 中（サーバ+API+管理画面） | 小 |
| 秘密情報の置き場 | アプリ（PKCE） | サーバ（既存方針と一致） | なし |
| 複数端末での共有 | × 端末ごとに認証 | ◎ サーバキャッシュ共有 | △ |
| 既存資産の流用 | 再生/保存は流用 | 再生/保存+`/api`+管理画面 流用 | 再生/保存流用 |
| マルチユーザー将来性 | ◎ 各自の Dropbox | × 単一アカウント | × |

## 推奨（暫定・要ユーザー確認）

- **当面の個人利用前提なら 案B（バックエンド経由）を推奨。**
  既存の秘密情報集約・`/api` + 管理画面パターンに素直に乗り、アプリに Dropbox 依存/OAuth を
  持ち込まずに「音声タブで一覧→追加→再生」が実現できる。キャッシュで Dropbox 負荷も抑えられる。
- **将来「各ユーザーが自分の Dropbox を繋ぐ」方向（TODO の複数ユーザー検討）に進むなら 案A**。
  その場合は App Folder スコープ + PKCE を前提に設計する。
- 案C は PoC・最小確認用として最短だが、要望 UX に届かないため本採用は見送り。

## 音声タブ UI / データモデルの初期案（案B ベース）

- `AppTab` に `.audio` を追加、`ContentView` にタブ追加（例: `Label("Audio", systemImage: "waveform")`）。
- 画面: Dropbox（サーバ経由）の音声フォルダ一覧を表示 → 「追加」でアプリに取り込み
  （ローカル保存）→ 一覧から再生（`TTSPlaybackService`）。
- 保存: `TTSAudioStore` を一般化するか、`AudioClipStore` を新設してローカルキャッシュ。
- SwiftData に「取り込んだ音声クリップ」エンティティを持たせるかは実装フェーズで判断
  （メタデータ管理が必要なら新エンティティ。※新エンティティ追加時は
  [[ios-swiftdata-new-entity-checklist]] に従う）。

## 影響範囲（実装フェーズの見込み・案B の場合）

- backend: `config.ts`（`audioDir` + Dropbox 認証情報）、`db.ts`（音声メタテーブル）、
  新規 `dropbox.ts`（Dropbox API クライアント）、`index.ts`（`/api/audio` 系）、
  `admin.ts`（音声一覧・試聴）。`.env` に Dropbox App Key/Secret/refresh token を追加。
- iOS: `AppTab`/`ContentView` にタブ追加、新規 `AudioView` + `AudioClipStore`、
  再生は `TTSPlaybackService` 流用。iOS は XcodeGen 管理のため
  ファイル追加後 `xcodegen generate`（[[ios-xcodegen-project]]）。
- 案A を採る場合: iOS に SwiftyDropbox（SPM）追加・OAuth・Keychain・URL スキーム。

## テスト方針（実装フェーズ）

- backend（案B）: Dropbox 認証成功、フォルダ一覧取得、ダウンロード→キャッシュ、
  2 回目はキャッシュ返却。管理画面で一覧・試聴。
- iOS: `xcodebuild` ビルド。音声タブで一覧表示→追加→再生→画面再訪で状態維持。
  実音声の確認はユーザーに依頼。

## 次アクション（このタスク = 調査の締め）

1. 上記比較をユーザーに提示し、**採用方式（A / B / C）を決定**する。
2. Dropbox 側の前提を確定: どのフォルダに音声を置くか、形式（mp3 / m4a / wav 等）。
   → 決定後、実装プラン（別ファイル）に落として次フェーズへ。
