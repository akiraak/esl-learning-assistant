# YouTube タイトルの自動取得（oEmbed）

## 目的・背景

レッスンコンテンツの YouTube 行は現在 `videoID` を表示している（`YouTubeLink.title` は既定 nil）。
キー不要の YouTube oEmbed でタイトルを取得して `title` を補完し、一覧表示を videoID から
タイトルへ差し替える。API キー・バックエンド変更は不要。

- oEmbed: `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=<id>&format=json`
  - 公開動画なら API キーなしで `title` 等を返す。非公開/削除済み等は 4xx → タイトル無し。

## 対応方針

### 取得タイミング（重要な判断）

**一覧行での遅延バックフィル**にする。追加時の同期取得は Add に待ち時間・失敗リスクを持ち込み、
既存（過去に追加済み）リンクを埋められない。行が表示されたとき `title == nil` なら oEmbed を
呼び、取得できたら `title` を永続化する（次回以降は再取得しない）。新規・既存を同じ経路で扱える。

- 取得失敗（オフライン/4xx/デコード失敗）時は `title` を nil のまま据え置き、`displayTitle` の
  videoID フォールバックで表示する（既存挙動）。
- `YouTubeRow.displayTitle` は既に「title があればそれ、無ければ videoID」なので、表示側の変更は不要。
  `title` が入った時点で SwiftData 変更通知により行が自動でタイトル表示に切り替わる。

### 新規: `Support/YouTubeOEmbed.swift`

- `static func fetchTitle(videoID:) async -> String?` … oEmbed を叩いて `title` を返す。失敗時 nil。
  - `URLSession.shared`、`timeoutInterval` 10s、200 以外/デコード失敗は nil。`os.Logger` に記録。
  - **UIテスト用スタブ**: UserDefaults キー `uiTestStubYouTubeTitle`（`-uiTestStubYouTubeTitle "..."`
    launch 引数）が非空なら実ネットワークを呼ばずその値を返す。タイトル差し替えの E2E を決定的にする。
- `static func endpoint(for videoID:) -> URL?` … エンドポイント URL 構築（`YouTubeURL.isValidID`
  で不正 ID を弾く）。純関数・ユニットテスト対象。

### 変更: `YouTubeRow.swift`

- `@Environment(\.modelContext)` を追加。
- `.task(id: link.id)` で `backfillTitleIfNeeded()` を実行。`title == nil` のときだけ取得・保存。

## 影響範囲

### 新規
- `Support/YouTubeOEmbed.swift`
- `ESLLearningAssistantTests/YouTubeOEmbedTests.swift`（endpoint 構築・不正 ID・スタブ短絡）

### 変更
- `Views/YouTubeRow.swift` … modelContext + `.task` バックフィル
- `ESLLearningAssistantUITests/LessonYouTubeAddUITests.swift` … stub launch 引数で
  「追加→videoID がタイトルへ差し替わる」を決定的に検証
- XcodeGen: 新規ファイル追加後は `xcodegen generate`

### 非対象
- 詳細画面（`YouTubeDetailView`）のナビタイトルは "YouTube" のまま（一覧表示が要件）。
- 追加時の同期取得はしない。

## テスト方針

- **ユニット**: `YouTubeOEmbed.endpoint` の URL 構築、不正 ID で nil、スタブキー設定時に短絡して
  その値を返す（実ネットワーク非依存）。
- **E2E**: launch 引数でスタブタイトルを注入し、YouTube 追加後に行が videoID から
  スタブタイトルへ差し替わること・その行から詳細へ遷移できることを確認（決定的・オフライン安全）。
- **手動**: 実ネットワークで実タイトルが表示されること、取得失敗時に videoID 表示へフォールバックすること。

## Step

- Step 1: `YouTubeOEmbed` サービス + `YouTubeRow` バックフィル
- Step 2: ユニットテスト + E2E テスト更新、`xcodegen generate`、build/test
