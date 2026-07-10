# TTSリキー移行（ttsPlainTextRekeyV1）コードの削除

## 目的・背景

2026-07-08 の `MarkdownPlainText` ブロック境界修正（コミット 24355ba）に伴い、既存TTS音声を
旧キー→新キーへ引き継ぐ一回きりの移行コード（`TTSCacheRekeyMigration` / `POST /api/tts/rekey`）を
導入した。移行は全端末で完了済み（`ttsPlainTextRekeyV1` フラグが立った）ため、橋渡しコードを
一式削除して後片付けする。

## 対応方針

### iOS（削除）

- `Sources/Services/TTSCacheRekeyMigration.swift` — ファイルごと削除
- `Sources/Support/MarkdownPlainText.swift` — `legacyPlainText` を削除。
  ヘッダの注意コメントは「キー変更時はリキー移行が必要」の警告を残しつつ、
  削除済みシンボルへの参照を git 履歴参照に書き換える
- `Sources/ContentView.swift` — 起動フック `.task { ... }` と、それ専用の
  `@Environment(\.modelContext)` プロパティを削除
- `Sources/Services/TTSAudioStore.swift` — 移行専用の `rekeyLocalFile` を削除
  （`key` / `save` / `localURL` 等は通常機能で使うため残す）
- テスト:
  - `ESLLearningAssistantTests/TTSCacheRekeyMigrationTests.swift` — ファイルごと削除
  - `MarkdownPlainTextTests.swift` — `testSingleParagraphMatchesLegacyOutput` /
    `testLegacyDropsBlockBoundaries` と `testNilAndEmptyReturnEmpty` 内の legacy 分を削除
  - `TTSAudioStoreTests.swift` — `rekeyLocalFile` セクション（4テスト）を削除
- ファイル削除後に `xcodegen generate` で pbxproj を再生成

### backend（削除）

- `src/index.ts` — `POST /api/tts/rekey` エンドポイントと `rekeyTtsAudio` の import を削除
- `src/ttsStore.ts` — `TtsRekeyStatus` 型・`rekeyTtsAudio` 関数と、
  移行専用になる `updateTtsAudioKey` の import を削除
- `src/db.ts` — `updateTtsAudioKey`（rekey 専用）を削除
- `test/ttsRekey.test.ts` — ファイルごと削除

## 影響範囲

- 未移行の端末が残っていた場合、その端末の既存全文読み上げ音声は「未生成」表示に戻り、
  ボタン押下で再合成（課金）される。機能自体は壊れない（前提: 全端末移行済みの確認)
- UserDefaults の `ttsPlainTextRekeyV1` フラグは無害なので掃除しない
- `backend/dist/` は gitignore 済みのビルド成果物のため触らない（次回ビルドで消える）

## テスト方針

- backend: `npm run build`（tsc で参照漏れ検出）+ `npm test`
- iOS: `xcodegen generate` 後、シミュレータで `xcodebuild test`（ユニットテスト全通過）
- `grep -rn "rekey\|legacyPlainText\|ttsPlainTextRekeyV1"` で残骸ゼロを確認
  （ドキュメント・DONE.md の記録は除く）
