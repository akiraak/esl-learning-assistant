# TTS用プレーンテキスト変換のブロック境界修正とキャッシュ移行

## 目的・背景

`MarkdownPlainText.plainText`（Photo / Docs の全文読み上げで共用）が
`AttributedString(markdown:, interpretedSyntax: .full)` でブロック境界の改行を落とすため、
見出しと直後の段落・リスト項目同士が区切りなしで連結されたテキストが TTS に渡っている。

例（実測。scratchpad の Swift スクリプトで再現確認済み）:

```
入力:  # The Sun and the Wind\n\nThe north wind and the sun argued.\n\n- first item\n- second item
現状:  "The Sun and the WindThe north wind and the sun argued.first itemsecond item"
```

このため合成音声が見出しと本文を息継ぎなしに読み上げてしまう。

### 制約: 変換結果は TTS キャッシュキーそのもの

変換結果は端末 `TTSAudioStore` / サーバ `tts_audio` 共通のキャッシュキー
`sha256("model|text")` の `text` になる。変換ロジックを変えると複数ブロックを含む
既存テキストのキーがすべて変わり、そのままでは既存の全文読み上げ音声（特に長文 Docs ×
pro モデル）が「未生成」扱いになって再合成課金が走る。**修正はキャッシュ移行とセットで行う。**

## 現状整理（コード上の事実）

- 変換: `ios/.../Sources/Support/MarkdownPlainText.swift` — `.full` でパースし `String(attributed.characters)` を返すだけ
- 利用箇所: `PhotoDetailView.swift`（`photo.ocrText`）と `DocumentDetailView.swift`（`document.extractedText`）の 2 箇所のみ。クイズ音声・単語読み上げは Markdown 変換を通らないため無影響
- 端末キャッシュ: `TTSAudioStore` が Application Support 配下に `<sha256>.wav` で保存
- サーバキャッシュ: `backend/src/ttsStore.ts` の `ttsCacheHash` が同一キーで `tts_audio` テーブル + `data/tts/<hash>.wav` を管理
- Markdown の原文（`ocrText` / `extractedText`）は端末の SwiftData にのみ存在し、サーバは変換後の `text` しか持たない。つまり **新キーを計算できるのは端末だけ**（旧テキストからブロック境界は復元不能）

## 対応方針

### 変換の修正方法（検証済み）

`.full` でパースした `AttributedString` の run を `presentationIntent.components` の
identity チェーン（`components.map(\.identity)`）でグルーピングし、ブロックごとの文字列を
`"\n\n"` で連結する。scratchpad での検証結果:

```
The Sun and the Wind\n\nThe north wind and the sun argued.\n\nfirst item\n\nsecond item\n\nBold paragraph here.
```

- 見出し・段落・リスト項目がすべて分離される（`components.last` だけだとリスト項目が連結されるため identity チェーン全体をキーにする）
- **単一段落のテキストは出力が従来と一致**するため、その分のキャッシュキーは不変（移行対象は複数ブロックのテキストのみ）
- パース失敗時は従来どおり原文を返す

### キャッシュ移行方針: 再合成なしのリキー（recommended）

旧キー→新キーへの「リキー」を端末主導で 1 回だけ行い、**再合成課金ゼロ**で既存音声を引き継ぐ。

- 旧変換ロジックを `MarkdownPlainText.legacyPlainText`（internal、移行専用）として温存し、端末が旧キーと新キーの両方を計算する
- 端末ローカル: 旧キーの `.wav` を新キー名にリネーム（オフラインでも成立、冪等）
- サーバ: 新設の `POST /api/tts/rekey` に `{ oldHash, newText, model }` を送り、`tts_audio` の行（text / text_hash / filename）とWAVファイル名を更新する

却下した代替案 — **残置＋必要時再生成**（過去のキー形式変更 sha256("voice|model|text")→sha256("model|text") と同じ扱い）:
実装は最小だが、長文 Docs × pro の再合成課金が発生しうるのが TODO の懸念そのもの。前回は
voice 設定廃止が理由でリキー不能だったが、今回は端末が新旧キーを両方計算できるためリキー可能。

## Phase 構成

### Phase 1: MarkdownPlainText の修正（iOS）

- `plainText` を presentationIntent ベースのブロック分割 + `"\n\n"` 連結に変更
- 旧実装を `legacyPlainText` として温存（doc コメントで「移行完了後に削除」と明記）
- ユニットテスト `MarkdownPlainTextTests` を新設:
  - 見出し+段落 / リスト / インライン強調（`**` 除去）の分離
  - **単一段落は旧実装と出力一致**（キャッシュキー安定性の回帰テスト）
  - nil / 空文字 / パース不能文字列のフォールバック

### Phase 2: サーバ rekey エンドポイント（backend）

- `ttsStore.ts` に `rekeyTtsAudio(oldHash, newText, model)` を追加:
  - `newHash = sha256(model|newText)` を計算。`oldHash === newHash` → unchanged
  - `oldHash` の行なし → not_found（移行済み or 未生成。冪等に 200 で返す）
  - `newHash` の行が既に存在（移行前に新テキストで生成済み）→ 旧行と旧ファイルを削除
  - 通常: WAV を `<newHash>.wav` にリネームし、行の text / text_hash / filename を更新
- `db.ts` に更新ヘルパー（`updateTtsAudioKey`）を追加
- `index.ts` に `POST /api/tts/rekey` を追加（text 長・model のバリデーションは `/api/tts` と同基準）
- テスト: `test/ttsRekey.test.ts`（node --test）。db がシングルトンでユニットテスト化が難しい場合は、
  4 分岐（unchanged / not_found / duplicate / rekeyed）を curl シナリオ + 管理画面 `/admin/tts` で手動検証し、その旨をプランに追記する

### Phase 3: 端末側の一括リキー移行（iOS）

- 新サービス `TTSCacheRekeyMigration`（Sources/Services）:
  - SwiftData から全 `Photo.ocrText` / `Document.extractedText` を取得
  - 各テキストで legacy / new の変換結果を比較し、差分があるものだけ対象化
  - モデル `"flash"` / `"pro"` の両方について: ローカル `.wav` をリネーム（`TTSAudioStore` にリネームヘルパー追加）→ `POST api/tts/rekey`
  - 起動時に 1 回実行（`ContentView.task` 等）。UserDefaults フラグ `ttsPlainTextRekeyV1` は**サーバ呼び出しがすべて成功した場合のみ**セットし、オフライン失敗時は次回起動で再試行（ローカルリネームは冪等なので安全）
- 移行が動かなかった場合の劣化パスは「未生成扱い→ボタン押下で再合成」であり、機能は壊れない

## 影響範囲

- iOS: `MarkdownPlainText.swift` / `TTSAudioStore.swift`（リネームヘルパー）/ 新規 `TTSCacheRekeyMigration.swift` / 起動フック（ContentView または App）
- backend: `index.ts` / `ttsStore.ts` / `db.ts`（`dist/` は生成物なので `npm run build` で更新）
- 無影響: クイズ音声・単語読み上げ（Markdown 変換を通らない）、単一段落のみの Photo/Docs（キー不変）
- 表示系（MarkdownUI での本文表示）は `MarkdownPlainText` を使っていないため無影響

## テスト方針

- iOS ユニットテスト: Phase 1 記載の `MarkdownPlainTextTests` + `TTSAudioStore` リネームの単体テスト
- backend: Phase 2 記載の rekey 4 分岐
- 結合確認（シミュレータ or 実機）:
  1. 修正前に複数ブロックの Photo/Docs で音声生成 → 修正版へ更新 → 起動時移行後、**再合成なしで**再生ボタンがそのまま出ること（サーバログに `tts: start` が出ないこと）
  2. 新規生成した音声が見出し・段落間にポーズを持つこと
  3. 管理画面 `/admin/tts` で対象行の text が改行入りに更新されていること

## 後片付け（移行が行き渡った後の別タスク）

- `legacyPlainText` と `TTSCacheRekeyMigration` の削除（TODO.md に完了時に追加する）

## 実施結果（2026-07-08、全 Phase 完了）

- Phase 1〜3 をプランどおり実装。テスト: iOS ユニット13件（MarkdownPlainText 6 / TTSAudioStore リキー4 /
  TTSCacheRekeyMigration.targets 3）+ backend 6件、全既存テストもグリーン
- Phase 2 のテストは手動 curl ではなく自動化できた: `config.ts` に `DATA_DIR` 環境変数の上書きを追加し、
  テストが import 前に一時ディレクトリへ向けてから `require` することで実 DB（backend/data）から隔離
  （import 巻き上げ回避のため require を使用。`test/ttsRekey.test.ts` 参照）
- 結合確認: 一時サーバ（DATA_DIR 隔離 + 別ポート）への curl で 4分岐 + 401/400 を確認し、
  リネーム後ハッシュが iOS 側 `TTSAudioStore.key` の計算値と一致することを確認。
  シミュレータ実起動で移行フックが完走し `ttsPlainTextRekeyV1` がアプリ prefs に永続化されることを確認
  （このシミュレータは対象ゼロの即完了パス。対象ありパスは各部の単体+curl 検証の組合せでカバー）
- デプロイ順の注意: backend を先にデプロイすること。エンドポイントが無い状態でアプリを更新しても
  端末移行は失敗→フラグ未設定のまま次回起動でリトライするので壊れはしないが、移行は完了しない
