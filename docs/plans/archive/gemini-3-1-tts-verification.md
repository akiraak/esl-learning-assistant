# Gemini 3.1 TTS の検証

## 目的・背景

- 現在の AI 音声合成は Gemini 2.5 TTS（`gemini-2.5-flash-preview-tts` / `gemini-2.5-pro-preview-tts`）を使用している（`backend/src/tts.ts:25-28`）。
- Google から後継の **`gemini-3.1-flash-tts-preview`** が提供開始された。2.5 世代からの世代交代モデルで、以下が公称の改善点:
  - 自然さの向上・低レイテンシ
  - 200 種以上のインライン音声タグ（`[whispers]` `[excited]` 等）による演出制御
  - 対応言語 70+（2.5 の約3倍）、ボイスは 30 種（既存利用中の `Leda` / `Aoede` も含まれる）
  - ストリーミング出力対応（TTS 系では 3.1 のみ）
- 本タスクでは 3.1 を実際に呼び出して品質・互換性・コストを検証し、既存の flash / pro からの置き換え（または選択肢追加）を判断する。

### 事前調査で判明している仕様（2026-07 時点）

| 項目 | gemini-3.1-flash-tts-preview | 参考: 2.5 flash / pro |
| --- | --- | --- |
| 料金（per 1M tokens） | 入力 $1.00 / 出力 $20.00 | flash: $0.5 / $10、pro: $1.0 / $20 |
| 無料枠 | あり（公式料金ページに Free tier 記載。2026-07-21 確認。当初調査の「なし」は誤り） | flash はあり、pro はなし |
| 出力形式 | PCM 24kHz / 16bit / mono（現行と同一） | 同左 |
| コンテキスト | 入力 8,192 / 出力 16,384 トークン | 32k |
| 音声トークン換算 | 25 tokens/秒 | 同左 |
| 備考 | SynthID 透かし自動付与。数分超の長尺で品質劣化の可能性と明記 | — |

### 料金比較と読み上げ箇所ごとのコスト予想（2026-07-21 実施）

公式料金ページ（https://ai.google.dev/gemini-api/docs/pricing）で確認した単価（Standard、per 1M tokens）:

| モデル | 入力(text) | 出力(audio) | Batch | 無料枠 |
| --- | --- | --- | --- | --- |
| gemini-2.5-flash-preview-tts | $0.50 | $10.00 | $0.25 / $5.00 | あり |
| gemini-2.5-pro-preview-tts | $1.00 | $20.00 | $0.50 / $10.00 | なし |
| gemini-3.1-flash-tts-preview | $1.00 | $20.00 | $0.50 / $10.00 | あり |

- **3.1 flash は 2.5 pro と同一単価（2.5 flash の2倍）**。音声トークンは 25 tokens/秒なので、出力コストは音声1分あたり 2.5 flash $0.015、2.5 pro / 3.1 $0.030。
- TTS モデル個別のレート制限は公式 rate-limits ページから消えており、AI Studio ダッシュボードでのみ確認可能（Phase 1 で無料枠の実用性を確認する）。

実 DB（`backend/data/db.sqlite` の `tts_audio`、277件・全て flash、累計 $0.29）の実測トークンに基づく、読み上げ箇所ごとの1回あたり生成コスト予想:

| 読み上げ箇所 | 現行モデル | 典型テキスト | 実測トークン(in/out) | 2.5 flash | 3.1（=2.5 pro） |
| --- | --- | --- | --- | --- | --- |
| 単語の発音（WordDetailView） | ユーザー設定（既定 flash） | 1語 ~17字 | 16 / 44 | $0.00045 | $0.0009 |
| 語義・例文（WordDetailView） | ユーザー設定（既定 flash） | 1文 ~62字 | 25 / 107 | $0.0011 | $0.0022 |
| クイズ audioText（1単語分 ≈6.7クリップ） | flash 固定（`QUIZ_TTS_MODEL`） | 1語〜2文 ~51字 | — | $0.006 | $0.012 |
| Photo/Document 長文（実測最長 1,188字） | ユーザー設定（既定 flash） | 数百〜数千字 | 284 / 1,845 | $0.019 | $0.037 |
| 同・5,000字換算（out≈1.55tok/字で外挿） | 〃 | — | ~1,200 / ~7,800 | ~$0.078 | ~$0.156 |
| 同・20,000字＝API上限換算 | 〃 | — | ~4,800 / ~31,000 | ~$0.31 | ~$0.62 |

読み上げ全履歴の累計が $0.29（うち手動 TTSButton $0.22 / クイズ $0.07）という規模なので、**短文系（単語・語義・例文・クイズ）は 3.1 化しても絶対額はごく小さい**。コストが実額として効くのは Photo/Document の長文のみ。3.1 は「数分超の長尺で品質劣化の可能性」が明記されているため、長文は 2.5 flash 据え置き（またはユーザー選択制）が有力。また 2.5 pro と同額なので、**設定の「pro」枠を 3.1 に差し替えるのは価格中立**（品質が pro 以上なら純増なし）。モデル切替はキャッシュキー（`sha256(model|text)`）が変わるため既存キャッシュは効かず、クイズを切り替えた場合は既存82クリップの再生成で一時費用 ~$0.15 が発生する。

**注意点（検証で必ず確認）**: 公式の speech-generation ガイドでは 3.1 向けに新しい `interactions` API（`response_format: {type: "audio"}` / `speech_config: [{voice: ...}]`）のコード例が出ている。現行実装の `v1beta/models/{model}:generateContent` + `responseModalities: ["AUDIO"]` + `prebuiltVoiceConfig` の呼び方がそのまま通るかが最大の互換性リスク。通らない場合は `tts.ts` に新しい呼び出しパスが必要になる。

## 対応方針

### Phase 1: API 疎通・互換性検証（スクリプト）

1. `backend/scripts/tts-long-check.ts` をモデル指定可能に拡張する（または検証用スクリプト `tts-gemini31-check.ts` を追加）。
2. `gemini-3.1-flash-tts-preview` を**現行と同じ `generateContent` リクエスト形式**で呼び、以下を確認:
   - 正常に音声が返るか（ダメなら `interactions` API で再試行し、必要な実装差分を記録）
   - `Leda`（chobi）/ `Aoede`（naruko）のボイス名がそのまま使えるか
   - 返却 PCM が 24kHz/16bit/mono で、既存の `pcmToWav` がそのまま使えるか
   - `usageMetadata`（input/output トークン）が取れてコスト計算が成立するか
   - 既存の英語スタイルプロンプト（`tts.ts:13-22`）が効くか・悪さをしないか
3. 長文（チャンク 1500 文字 × 複数、`CHUNK_MAX_CHARS`）での動作、リトライ・途中切れ検出ロジックとの相性を確認。入力コンテキストが 8,192 トークンに縮小されているため、チャンクサイズが安全圏か確認する。

**コスト記録の注意（検証時）**: `estimateCostUsd` は未知モデルに対して **$0 を返し**、その値が合成時に `tts_audio.cost_usd` へ焼き込まれる（`ttsStore.ts:46-49`）。単価登録前に `ttsStore` / `POST /api/tts` 経由で合成すると管理画面のコスト表示が恒久的に $0 になるため、検証スクリプトは **`tts.ts` の `synthesizeSpeech` を直接呼び、DB には書き込まない**（コストは `usageMetadata` のトークン数 × 公称単価からスクリプト内で算出して記録する）。

### Phase 2: 品質・レイテンシ・コスト比較

1. 実データ相当のテキスト 4 種で 2.5 flash / 2.5 pro / 3.1 を同一ボイスで生成:
   - 単語の読み上げ（短文）
   - 例文（1〜2 文）
   - 長文パッセージ（Photo/Document 由来、数千文字）
   - クイズのリスニング用 `audioText`
2. 聴き比べ（自然さ・発音・速度感）と、レイテンシ・生成コスト（$/音声分）を記録して比較表を作る。
3. 音声タグ（`[whispers]` 等）は学習テキストに角括弧が含まれた場合に誤発動しないかだけ確認する（積極活用は本タスクの範囲外）。

### Phase 3: 採用判断と組み込み（採用時のみ）

採用する場合の変更箇所:

- `backend/src/pricing.ts`: `DEFAULT_TTS_PRICING` に 3.1 の単価（$1.00 / $20.00）を追加。**モデルIDでの合成を最初に本番経路へ流すより前に必ず追加する**（未知モデルは $0 記録になるため。Phase 1 の注意参照）。このテーブルに追加すれば以下は自動で追従する:
  - 管理画面「AI料金（単価）」ページの一覧行（`admin.ts` は `DEFAULT_TTS_PRICING` のキーを列挙して表示）
  - `pricingSync.ts` の24時間ごと Google 公式ページ自動更新（`applyFetchedTtsPricing` はテーブルのキーを走査。セクション切り出しの境界判定にも他モデルIDとして効く）。ただし料金ページ上の 3.1 セクションが `Input price … $x (text)` / `Output price … $x (audio)` の既存パターンで抽出できるかは要確認
  - コスト集計のキャリア判定（`providerForModel` はテーブル所属 → `gemini-` 接頭辞の順で判定）
- `backend/src/admin.ts`: `modelUsage()`（`admin.ts:1456-1457`）に 2.5 のモデルIDがハードコードされているため、3.1 の行を追加（単価ページの「用途」列表示）。その他の TTS 一覧・利用料金ページはモデル文字列と保存済み `cost_usd` をそのまま表示するため影響なし（要目視確認）
- `backend/src/tts.ts`: `MODELS` に 3.1 を追加（既存 flash/pro を残すか置き換えるかは Phase 2 の結果で判断）
- `backend/src/ttsStore.ts`: `QUIZ_TTS_MODEL` を切り替えるか判断（3.1 flash は 2.5 flash の2倍の単価である点に注意）
- iOS: `AppSettingsKeys.swift` のモデルキー（`"flash"` / `"pro"`）と `SettingsView.swift` の選択肢を更新。`quizTTSModel` はバックエンドと一致させる

キャッシュキーは `sha256(model|text)` にモデル名が入るため、既存 WAV キャッシュはそのまま有効。新モデル分は新規生成となりコストが発生する（一括再生成はしない）。

## 影響範囲

- 検証のみ（Phase 1-2）: `backend/scripts/` 配下の検証スクリプトのみ。プロダクトコードへの変更なし。API 呼び出しコストが発生（3.1 は無料枠なし）。
- 採用時（Phase 3）: `backend/src/tts.ts` / `pricing.ts` / `pricingSync.ts` / `ttsStore.ts`、iOS `AppSettingsKeys.swift` / `SettingsView.swift`。

## テスト方針

- Phase 1-2: 検証スクリプトの実行結果（WAV 生成・秒数・トークン数・レイテンシ）を本プランファイルに追記して記録する。生成 WAV は実機 or シミュレータでの再生確認。
- Phase 3: 既存 backend テスト（`backend/test/`）の通過、iOS からの `POST /api/tts` 実機動作確認（単語・長文・クイズ事前生成）、管理画面での一覧・試聴・コスト表示確認。加えて「AI料金（単価）」ページで 3.1 の行（単価・用途列）が表示されること、「今すぐ更新チェック」で Google 公式ページから 3.1 の単価が取得できる（採用見送りログが出ない）ことを確認。TTS 一覧で新規合成行の `cost_usd` が $0 でないことも確認する。

## 検証・実装記録（2026-07-21 完了）

### Phase 1 結果: 互換性は完全（`interactions` API への移行不要）

検証スクリプト `backend/scripts/tts-gemini31-check.ts`（DB 非書き込み・モデルID直指定）で確認:

- 現行の `v1beta/models/{model}:generateContent` + `responseModalities: ["AUDIO"]` + `prebuiltVoiceConfig` が **3.1 でそのまま通る**
- `Leda`（chobi）/ `Aoede`（naruko）のボイス名はそのまま使用可
- 返却 PCM は `audio/l16; rate=24000; channels=1`（24kHz/16bit/mono）で `pcmToWav` 互換
- `usageMetadata`（promptTokenCount / candidatesTokenCount）取得可、コスト計算成立
- 英語スタイルプロンプト前置きも問題なし。角括弧入りテキスト（`[see Figure 2]` 等）も finishReason=STOP で正常合成（音声タグ誤発動の聴感確認用 WAV を生成済み）
- 長文はチャンク 1,430字＝入力298トークンで、縮小後の入力上限 8,192 トークンに対し十分安全

実測（2026-07-21、単価 $1.00/$20.00 で算出）:

| ケース | 文字数 | tokens in/out | 音声秒 | chars/s | コスト | レイテンシ |
| --- | --- | --- | --- | --- | --- | --- |
| 単語 | 11 | 15 / 67 | 2.1 | 5.3 | $0.0014 | 2.0s |
| 例文 | 85 | 28 / 192 | 6.0 | 14.2 | $0.0039 | 4.3s |
| 角括弧文 | 124 | 47 / 390 | 12.2 | 10.2 | $0.0079 | 7.7s |
| 長文チャンク1 | 1,430 | 298 / 3,990 | 124.7 | 11.5 | $0.0801 | 59.0s |
| 長文チャンク2 | 1,200 | 248 / 3,147 | 98.3 | 12.2 | $0.0632 | 46.8s |

読み上げ速度は 2.5 flash 実測（~16 chars/s）よりやや遅く、音声が長くなる分、実効コストは単価差2倍よりやや大きい（長文で実測 約2.6倍）。打ち切り検知（30 chars/s 閾値）・リトライロジックとの相性も問題なし。

### 採用判断

ユーザー判断で **全読み上げ箇所を 3.1 に切り替え**（Phase 2 の聴き比べは省略。検証 WAV はセッションのスクラッチパッド `tts31/` に生成済み）。

### Phase 3 実装: `flash31` キー追加方式

プラン原案の「flash/pro の差し替え」ではなく **新モデルキー `flash31` の追加**にした。理由:

- `tts_audio.model` は tier キー（"flash"/"pro"）で保存され、コスト集計時に `MODEL_PRESETS` で現在のモデルIDへ読み替える（`db.ts:1740`）。既存キーを 3.1 に差し替えると **2.5 世代の履歴行が 3.1 として表示されてしまう**
- 旧 iOS クライアントは "flash" を送ってくるため、受付を残す必要がある（旧キーは 2.5 のまま動き続ける）

変更内容:

- `pricing.ts`: `DEFAULT_TTS_PRICING` に `gemini-3.1-flash-tts-preview` $1.00/$20.00 を追加（合成経路より先に反映済み）
- `tts.ts`: `ModelKey` に `"flash31"` 追加、`MODEL_PRESETS.flash31 = "gemini-3.1-flash-tts-preview"`
- `ttsStore.ts`: `QUIZ_TTS_MODEL = "flash31"`、`WORD_READING_MODELS = ["flash31", "flash", "pro"]`、`regenerateWordReadingAudio` は flash31 を常に（再）生成＋旧世代はキャッシュ有りのみ再生成
- `index.ts`: `/api/tts` のモデル検証がハードコード（`!== "flash" && !== "pro"`）だったのを `model in MODEL_PRESETS` に修正
- `admin.ts`: `modelUsage()` に 3.1 の用途行を追加、2.5 は「旧」表記
- iOS `AppSettingsKeys.swift`: `fallbackServerTTSModel` / `quizTTSModel` を `"flash31"` に。起動時マイグレーションで保存済み `ttsModel` の "flash"/"pro" を "flash31" へ読み替え（テスト `AppSettingsKeysMigrationTests.swift` 追加）
- iOS `SettingsView.swift`: Picker を On-Device / Gemini 3.1 Flash TTS の2択に（2.5 の選択肢を廃止）

キャッシュキーは "flash31|text" で新規になるため、全箇所オンデマンドで新規生成（旧 WAV は残るが無害）。クイズ音声は新旧アプリでモデルキーが異なる移行期間中、旧アプリ分だけ 2.5 flash がオンデマンド合成される（自己修復経路、コスト僅少）。

### テスト結果

- backend: `tsc --noEmit` / テスト48件パス
- 実サーバ E2E: `POST /api/tts {text:"zebra", model:"flash31"}` → HTTP 200・WAV 61,484 bytes・`tts_audio` 行 `cost_usd=$0.00083`（**$0 でないことを確認**）。2回目はキャッシュヒット（latency 0ms）
- 料金自動更新: Google 公式ページ実HTMLに対し `applyFetchedTtsPricing` で 3モデルとも抽出成功・採用見送りなし（サーバ起動時の pricing-sync も成功ログ確認）
- 管理画面: `/admin/pricing`（3.1 の行）・`/admin/tts`（flash31 行）・`/admin/usage`（3.1 モデルID表示）を確認
- iOS: シミュレータビルド成功、ユニットテスト9件（マイグレーション6件含む）パス。実機での聴感確認は今後の通常利用で

## 参考リンク

- [Gemini 3.1 Flash TTS Preview モデルページ](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-tts-preview)
- [Speech generation ガイド](https://ai.google.dev/gemini-api/docs/speech-generation)
- [Gemini API 料金](https://ai.google.dev/gemini-api/docs/pricing)
- [Google 発表ブログ](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-1-flash-tts/)
- 過去の設計経緯: `docs/plans/archive/gemini-tts-model-selection.md`, `gemini-tts-voice-selection.md`, `tts-long-text.md`
