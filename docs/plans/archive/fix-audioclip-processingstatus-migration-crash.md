# Audioタブでアプリが落ちる: AudioClip.processingStatus のマイグレーションクラッシュ修正

## 目的・背景

アプリを起動して Audio タブを開くと落ちる。以前に登録した音声データを持つ環境でのみ発生。

### 再現・確定した根本原因

Phase 2 (commit `1803434`) で `AudioClip` に**非オプショナルな** enum 属性
`var processingStatus: AudioProcessingStatus = .pending` を追加した。SwiftData の
ライトウェイトマイグレーションは、既存行に対して Swift の既定値 `.pending` を
**埋め戻さない**。そのため Phase 2 より前に登録済みの AudioClip 行は
`ZPROCESSINGSTATUS` カラムが **NULL** のまま残る。

Audio タブ描画時に `clip.processingStatus`（`AudioClipRow.transcriptStatusBadge` /
`AudioDetailView.transcriptSection`）を読むと、SwiftData が NULL を非オプショナル
enum へ強制キャストしてトラップする:

```
Could not cast value of type 'Swift.Optional<Any>' to 'ESLLearningAssistant.AudioProcessingStatus'
```

シミュレータ実ストアに `ZPROCESSINGSTATUS = NULL` の行を注入して起動 → 同一クラッシュを再現。
同じ行を `'pending'` に更新すると正常描画（クラッシュせず）することも確認済み。

これはメモリ `swiftdata-codable-migration-pitfall` に記録済みの地雷そのもの。
新品ストア（シミュレータ・テスト）では再現せず、既存行のある環境だけで壊れるため
Phase 2 の検証をすり抜けた。

## 対応方針

メモリ推奨・既存イディオム（`WordReviewState.stepIndexStorage`）に合わせ、
**nullable ストレージ ＋ computed 既定値**にする。

```swift
private var processingStatusStorage: AudioProcessingStatus?
var processingStatus: AudioProcessingStatus {
    get { processingStatusStorage ?? .pending }
    set { processingStatusStorage = newValue }
}
```

NULL は `nil` としてデコードでき（optional cast は成功）、computed が `.pending` を返すため
クラッシュしない。公開 API（`processingStatus`）は非オプショナルのまま維持し、
既存の `switch clip.processingStatus` 呼び出しは無改修。

## 影響範囲

- `ios/.../Models/AudioClip.swift`: プロパティ定義・`init` 代入
- 呼び出し側（`AudioView` / `AudioDetailView` / サービス層）は API 不変なので改修不要
- カラム名が `ZPROCESSINGSTATUS` → `ZPROCESSINGSTATUSSTORAGE` に変わる。Phase 2 以降に
  文字起こし済みの少数クリップは status が既定 `.pending` 表示に戻る（transcript 本文は
  別カラムで保持されるため、再文字起こし1タップで復帰）。要検証で最終判断。

## 同型の潜在地雷（別途）

- `Word.aiInfoStatus`（`= .none`）— 同じ非オプショナル enum パターン
- `Photo.processingStatus`（既定値なし）— さらに脆い
既存 Word/Photo 行を持つ環境では同様に落ちうる。今回は AudioClip を修正・検証し、
Word/Photo の横展開はユーザー判断で別対応。

## テスト方針

- シミュレータ実ストアに `ZPROCESSINGSTATUS = NULL` の旧行を注入 → 修正ビルドで
  Audio タブがクラッシュせず `.pending`（Transcribe ボタン）表示になることを確認
- `'completed'` + transcript 本文入りの行でも挙動確認
- 可能なら「旧スキーマ + 既存行 → 現行スキーマ再オープン」の永続化テストを追加

## 実施結果（2026-07-06）

- **再現**: シミュレータ実ストアに `ZPROCESSINGSTATUS = NULL` の AudioClip 行を注入 → Audio タブ起動で
  `Could not cast value of type 'Swift.Optional<Any>' to 'AudioProcessingStatus'` で即クラッシュを確認。
  同行を `'pending'` にすると正常描画（クラッシュせず）。
- **AudioClip 修正**: `processingStatus` を `private var processingStatusStorage: AudioProcessingStatus?` +
  computed（NULL→`.pending`）に変更。旧行 NULL + `completed` 行を用意した実ストアで修正ビルドを起動 →
  クラッシュせず両行が `.pending` 表示（列は `ZPROCESSINGSTATUSSTORAGE` へ移行）。※当日実装機能のため
  非pending行はほぼ無く、値保全は不要と判断し単純パターンを採用。
- **Word.aiInfoStatus 横展開**: 同型の後付け非オプショナル enum（`5194335` で Word 追加後に追加）。
  既存 aiInfo を隠さないよう `@Attribute(originalName: "aiInfoStatus")` + storage/computed（NULL→`.none`）で修正。
  実ストアに NULL 行 + `completed` 行を注入 → 起動でクラッシュせず、`completed` が
  `ZAIINFOSTATUSSTORAGE` に**保全**されることを確認。
- **Photo.processingStatus**: Photo モデルと同一コミット（`cee7457`）導入＝元スキーマ。既存行に NULL は
  発生しないため据え置き（触ると既存値を無駄に失うだけ）。`Word.reviewState` も同様に元スキーマで安全。
- 変更ファイル: `Models/AudioClip.swift`, `Models/Word.swift`。呼び出し側は API 不変で無改修。
  全ビルド成功、Audio/Words タブとも実機同等の実ストアでクラッシュ無しを確認済み。
- 未了: 永続化ユニットテストの追加、コミット。
