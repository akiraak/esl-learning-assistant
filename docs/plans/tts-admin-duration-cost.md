# 管理画面TTS一覧に音声の長さと生成料金を表示

## 目的・背景

管理画面の TTS一覧（`/admin/tts`）には現在 ID・作成日時・テキスト・声・モデル・サイズ・試聴・削除しか表示されておらず、
「どれくらいの長さの音声か」「合成にいくらかかったか」が把握できない。
OCR や単語情報生成のログには料金（cost_usd）を記録しているのに、TTS だけコストが見えない状態を解消する。

## 現状整理

- `tts_audio` テーブル（`backend/src/db.ts`）: `created_at, text, voice, model, text_hash, filename, byte_size` のみ。トークン数・料金の記録なし
- `synthesizeChunk`（`backend/src/tts.ts`）: Gemini レスポンスから `inlineData`（音声）だけ取り出し、`usageMetadata`（トークン数）は捨てている
- WAV フォーマットは固定（24kHz / 16bit / mono、`tts.ts` の `SAMPLE_RATE` / `BITS` / `CHANNELS`）。ヘッダは 44 バイト
- `pricing.ts` は Claude モデル専用の単価表。Gemini TTS の単価は未定義

## 対応方針

### 音声の長さ

DB 変更なしで `byte_size` から算出する。フォーマットが固定なので:

```
durationSec = (byte_size - 44) / (24000 * 2 * 1)   // sampleRate * bytesPerSample * channels = 48000 bytes/sec
```

既存行にも遡って表示できる。表示は `m:ss` 形式（例: `2:07`）。

### 生成料金

Gemini API レスポンスの `usageMetadata`（`promptTokenCount` / `candidatesTokenCount`）を取得して実トークン数から計算し、DB に保存する。

- 単価表を `pricing.ts` に追加（**実装時に Google 公式の最新価格を確認して反映する**）:
  - `gemini-2.5-flash-preview-tts`: input $0.50 / output $10.00（per 1M tokens、要確認）
  - `gemini-2.5-pro-preview-tts`: input $1.00 / output $20.00（per 1M tokens、要確認）
- チャンク分割合成のため、リクエスト全体のトークン数は成功チャンク分の合算とする（リトライで失敗した試行分は計上しない割り切り）
- 既存行はトークン記録が無いため料金は「—」表示（`input_tokens = 0 AND output_tokens = 0` を未記録とみなす）

## 実装ステップ

### Step 1: DB — tts_audio にトークン・料金カラム追加（backend/src/db.ts）

- `CREATE TABLE` に `input_tokens INTEGER NOT NULL DEFAULT 0` / `output_tokens INTEGER NOT NULL DEFAULT 0` / `cost_usd REAL NOT NULL DEFAULT 0` を追加
- 既存 DB 向けに `PRAGMA table_info(tts_audio)` によるカラム有無チェック → `ALTER TABLE ADD COLUMN` の後方互換マイグレーション（requests テーブルと同じパターン）
- `TtsAudioRow` インターフェイスと `upsertTtsAudio` に3カラムを追加。`ON CONFLICT ... DO UPDATE SET` にも追加する
  （ファイル欠損からの再合成時に新しいトークン数・料金で上書きするため）

### Step 2: tts.ts — usageMetadata の取得と集計

- `GeminiResponse` に `usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number }` を追加
- `synthesizeChunk` の戻り値を `{ pcm: Buffer; inputTokens: number; outputTokens: number }` に変更
- `synthesizeSpeech` の戻り値を `{ wav: Buffer; inputTokens: number; outputTokens: number }` に変更（全チャンクの合算）

### Step 3: pricing.ts — Gemini TTS 単価と料金計算

- `PRICING_PER_MILLION_TOKENS` に Gemini TTS 2モデルのエントリを追加（既存の `estimateCostUsd` をそのまま使えるようにモデルID をキーにする）
- 単価は実装時に https://ai.google.dev/pricing で確認して記載する

### Step 4: index.ts — /api/tts で料金を計算して保存

- `synthesizeSpeech` の新しい戻り値からトークン数を受け取り、`estimateCostUsd(MODEL_PRESETS[model], inputTokens, outputTokens)` で計算
- `upsertTtsAudio` に `inputTokens / outputTokens / costUsd` を渡す
- 成功ログにトークン数と料金を出力する（例: `tokens=in:120/out:3400 cost=$0.0345`）

### Step 5: admin.ts — TTS一覧に「長さ」「料金」列を追加

- `byte_size` から長さを算出するヘルパー（`m:ss` 表示）を追加し、「サイズ」列の隣に「長さ」列を追加
- 「料金」列を追加。`input_tokens === 0 && output_tokens === 0` の行（マイグレーション前の既存行）は「—」、それ以外は `$0.0000` 形式（4桁）
- 一覧上部の「全N件」の横に料金合計を表示する（記録がある行のみの合算である旨を併記）

## 影響範囲

- `backend/src/db.ts` — スキーマ・マイグレーション・upsert
- `backend/src/tts.ts` — 戻り値の型変更（呼び出し元は index.ts のみ）
- `backend/src/pricing.ts` — 単価表追加
- `backend/src/index.ts` — /api/tts ハンドラ
- `backend/src/admin.ts` — TTS一覧画面
- iOS 側・API レスポンス形式（audio/wav バイナリ）には変更なし

## テスト方針

- `npm run build`（tsc）で型変更の波及漏れがないことを確認
- 既存 DB（カラム無し）でサーバを起動し、マイグレーションが走って一覧が開けること・既存行の長さが表示され料金が「—」になることを確認
- iOS またはcurl で `/api/tts` を1回叩き、新規行にトークン数・料金が記録され一覧に表示されることを確認
- キャッシュヒット時に料金が二重計上されないこと（既存行の値が維持されること）を確認
- 長さ表示の妥当性: 実際に試聴して表示秒数とおおよそ一致することを確認
