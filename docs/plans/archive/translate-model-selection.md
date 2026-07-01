# 翻訳ステップを別モデル（Haiku最新版）に変更できるようにする

## 目的・背景

現状 `backend/src/ocrTranslate.ts` はOCR（画像→英語文字起こし）と翻訳（英語→目的言語）を
1回のClaude API呼び出し（構造化出力でocrText/translatedTextを同時取得）で行っており、
モデルは `config.model`（既定 `claude-sonnet-5`）1つに固定されている。

翻訳ステップだけ別モデル（Haikuの最新版）に変更できるようにしたい。画像認識が必要なOCRは
引き続き高精度なモデル（Sonnet等）を使い、テキストのみの翻訳は安価な最新Haikuに切り替えて
コストを下げる、という使い分けができるようにする。

## 対応方針

### Step 1: OCRと翻訳の呼び出しを2回のAPI呼び出しに分割する

- `backend/src/ocrTranslate.ts` を次の2関数に分割する。
  - `ocrImage(imageBase64, mediaType, model)`: 画像→Markdown文字起こし（ocrText）。構造化出力継続。
  - `translateText(ocrText, targetLanguageCode, model)`: ocrTextをテキスト入力として渡し、
    目的言語へのMarkdown翻訳（translatedText）を取得。画像は渡さずテキストのみ。
- `ocrAndTranslate` は上記2関数を順に呼び出し、それぞれのモデル名・入力/出力トークン数を
  まとめて返すようにする。

### Step 2: 翻訳用モデルを設定可能にする

- `backend/src/config.ts` に `translateModel` を追加する。環境変数 `ANTHROPIC_TRANSLATE_MODEL`、
  未設定時のデフォルトは最新のHaiku（`claude-haiku-4-5`。既存 `pricing.ts` に価格定義済み）。
- 既存の `config.model` は「OCR用モデル」という意味合いになるため `config.ocrModel` にリネームし、
  環境変数名 `ANTHROPIC_MODEL` は据え置く（後方互換）。
- `backend/.env.example` に `ANTHROPIC_TRANSLATE_MODEL=claude-haiku-4-5` を追記する。

### Step 3: DBスキーマをOCR/翻訳それぞれのモデル・トークン数を記録できるようにする

- `backend/src/db.ts` の `requests` テーブルで `model`/`input_tokens`/`output_tokens` を
  `ocr_model`/`ocr_input_tokens`/`ocr_output_tokens` にリネームし、
  `translate_model`/`translate_input_tokens`/`translate_output_tokens` を新設する。
  `cost_usd` は引き続きOCR+翻訳の合計コストを保持する。
- 既存DB（`backend/data/db.sqlite`）に対しては起動時に `PRAGMA table_info` でカラム有無を
  確認し、無ければ `ALTER TABLE ... RENAME COLUMN` / `ADD COLUMN` で後方互換マイグレーションする
  （既存ログ件数は少ないが、削除せず残す）。

### Step 4: ルートハンドラ・adminの表示を更新する

- `backend/src/index.ts` の `/api/ocr-translate` で新しい`ocrAndTranslate`の戻り値を使い、
  OCR分・翻訳分それぞれのコストを`estimateCostUsd`で計算して合算した値を`cost_usd`として保存する。
- `backend/src/admin.ts` の一覧・詳細ページで、モデル欄をOCRモデル・翻訳モデルの2行表示に変更する
  （トークン数・コストも可能な範囲で内訳が分かるようにする）。

## 影響範囲

- `backend/src/ocrTranslate.ts`
- `backend/src/config.ts`
- `backend/src/db.ts`
- `backend/src/index.ts`
- `backend/src/admin.ts`
- `backend/.env.example`

## テスト方針

- `npm run build`（backend）でビルド確認。
- 既存の `backend/.env` に設定済みの実APIキーを使い、`run-server.sh` でサーバー再起動後
  `/api/ocr-translate` に実画像（`backend/data/images/`配下の既存ファイル）を投げて、
  OCRはSonnet・翻訳はHaikuの最新版で実行されること、`/admin`でモデル・コストが
  OCR/翻訳別に表示されることを確認する。
- 既存ログ（マイグレーション前のデータ）が admin 一覧・詳細ページでエラーなく表示されることを確認する。
