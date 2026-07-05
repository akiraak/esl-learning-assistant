# 音声のアプリ取り込み・レッスン紐付け・既存プレイヤー再生

前提: [audio-tab-dropbox-implementation.md](audio-tab-dropbox-implementation.md) で Dropbox 連携（案A）と
Audioタブの「その場再生」までは実装済み。本タスクはその発展。

## 目的（ユーザー要望）

1. Dropbox からファイルを **DL してアプリの正式データとして取り込む**（取り込み後は Dropbox 未接続でも再生可）
2. 取り込んだ音声を **レッスンに紐付ける**（単語と同様、レッスン非依存の音声も可 = 紐付け任意）
3. 再生は **既存の `TTSPlayerBar`**（`TTSPlaybackService`）を流用

決定事項（ユーザー確認済み）:
- Audioタブ = **取り込み済みライブラリ** + 「Import from Dropbox」でブラウザをシート表示
- レッスン紐付けは **両方から**: Audioタブのクリップ→レッスン選択 / レッスン詳細の「Audio」セクション→取り込み
- `AudioClip.lesson` は **任意**（未紐付けのライブラリ音声を許容）

## データモデル（写真=Photo を手本にする）

**新エンティティ `AudioClip`（`@Model`）** — `Sources/Models/AudioClip.swift`:
- `id: UUID`
- `title: String`（編集可。既定は Dropbox ファイル名から拡張子を除いたもの）
- `audioFileName: String`（`AudioStorage` 内の実ファイル名 `UUID.ext`）
- `sourcePath: String?`（Dropbox の pathLower。重複取り込み判定・参照用）
- `byteSize: Int`
- `importedAt: Date`
- `lesson: Lesson?`（任意の紐付け）

**`Lesson` に追加**:
```swift
@Relationship(deleteRule: .cascade, inverse: \AudioClip.lesson)
var audioClips: [AudioClip] = []
```
（既存 `photos` と同じ作法。レッスン削除で紐付きクリップも消える）

新エンティティ追加の作法は [[ios-swiftdata-new-entity-checklist]] に従う:
- **全 ModelContainer 登録**: `ESLLearningAssistantApp.swift`（本番コンテナ）と、各 Preview /
  `SettingsView` のリセット処理にある `for: [Class.self, Lesson.self, Photo.self, ...]` 配列
  すべてに `AudioClip.self` を追加（計 9 箇所）。
- **`DebugDataCleaner`**: `deleteAllAudioClips(context:)` を新設し `deleteAllData` から呼ぶ。
  `deleteAllClasses` / `deleteClass` は紐付きクリップの実ファイルも削除（写真と同様、
  削除前にファイル名を集める）。全削除時は `AudioStorage.deleteAll()`。
- マイグレーション: 新テーブル＋Lessonへ to-many リレーション追加 = ライトウェイトで開ける想定
  （既存埋め込み Codable への非オプショナル追加ではないため [[swiftdata-codable-migration-pitfall]]
  の地雷は踏まない）。

**`AudioStorage`（`Sources/Support/AudioStorage.swift`）** — `PhotoStorage` を手本に:
- `Documents/Audio/` に `UUID.ext` で保存。`save(data:ext:) -> String` / `url(fileName:) -> URL` /
  `delete(fileName:)` / `deleteAll()`。
- 既存の `AudioClipStore`（Application Support/audio、Dropboxパス鍵のブラウズ用キャッシュ）は
  本タスクで役割を終えるため撤去し、取り込みは `AudioStorage` に一本化する。

## Phase 1: モデル・ストレージ・登録

上記 `AudioClip` / `Lesson.audioClips` / `AudioStorage` を追加、全 ModelContainer 登録、
`DebugDataCleaner` 拡張、`AudioClipStore.swift` 削除。

## Phase 2: Dropbox 取り込みピッカー

現行 `AudioView` の Dropbox 一覧部分を **`DropboxImportView`** に切り出す:
- 引数 `targetLesson: Lesson?`（レッスン画面から開くときは固定、Audioタブからは nil→後で割当 or 未紐付け）。
- 未接続なら Connect、接続済みなら Dropbox の音声一覧。
- 各行: 既取り込み（`sourcePath` 一致の `AudioClip` あり）はチェック表示、未取り込みは取り込みボタン。
- 取り込み: `DropboxService.download` → `AudioStorage.save` → `AudioClip` を作成して
  `modelContext.insert`（`lesson = targetLesson`、`title` = ファイル名、`sourcePath` = pathLower）。
- シートとして提示し、完了で閉じる。

## Phase 3: Audioタブ = ライブラリ

`AudioView` を作り替える:
- `@Query(sort: \AudioClip.importedAt, order: .reverse)` で一覧。
- 空なら「Import from Dropbox」導線。ツールバー/上部に Import ボタン（→ `DropboxImportView` シート）。
- 行: タイトル、紐付くレッスン名（あれば）、再生/停止。行タップで再生。
- 再生は画面共有の `@StateObject TTSPlaybackService` ＋ `.safeAreaInset(edge:.bottom)` に `TTSPlayerBar`。
- スワイプ削除（行削除で `AudioStorage.delete` も実行）。
- 行の詳細 or コンテキストメニューで **タイトル編集**・**レッスン割当**（Class/Lesson ピッカー）。
  - レッスン割当 UI は既存の Class→Lesson 構造（`ClassLessonSwitcherView` 相当）を流用/簡易版。

## Phase 4: レッスン画面に Audio セクション

`LessonsView.lessonContent` に `audioSection(lesson)` を追加（Words と Memo の間あたり）:
- `lesson.audioClips` を一覧（`importedAt` 降順）。空なら "No audio yet"。
- ヘッダーの「＋」で `DropboxImportView(targetLesson: lesson)` シート。
- 行タップで再生。`LessonsView` に音声用 `TTSPlaybackService` ＋ `TTSPlayerBar`（`.safeAreaInset`）を追加。

## 影響範囲

- 新規: `Models/AudioClip.swift`, `Support/AudioStorage.swift`, `Views/DropboxImportView.swift`。
- 変更: `Models/Lesson.swift`（`audioClips`）, `Views/AudioView.swift`（ライブラリ化）,
  `Views/LessonsView.swift`（Audioセクション＋プレイヤー）, `Support/DebugDataCleaner.swift`,
  全 ModelContainer 登録 9 箇所, `ESLLearningAssistantApp.swift`。
- 撤去: `Services/AudioClipStore.swift`。
- backend 変更なし。iOS はファイル増減があるため `xcodegen generate`（[[ios-xcodegen-project]]）。

## テスト方針

- `xcodebuild` ビルド。可能なら `AudioStorage` の簡易ユニットテスト。
- 手動（シミュレータ/実機）:
  - Audioタブ Import→Dropbox から取り込み→ライブラリに出る→`TTSPlayerBar` で再生。
  - Dropbox を Disconnect しても取り込み済みは再生できる（正式データ化の確認）。
  - クリップにレッスンを割り当て→レッスン画面の Audio セクションに出る。
  - レッスン画面から Import→そのレッスンに紐付く。
  - クリップ削除でファイルも消える。レッスン削除で紐付きクリップも消える。

## Phase 分割（TODO 子タスク）

- [ ] Phase 1: AudioClip / Lesson.audioClips / AudioStorage / 全登録 / DebugDataCleaner
- [ ] Phase 2: DropboxImportView（取り込み）
- [ ] Phase 3: Audioタブ ライブラリ化（再生バー・編集・割当・削除）
- [ ] Phase 4: レッスン画面 Audio セクション
- [ ] Phase 5: ビルド確認・手動テスト依頼
