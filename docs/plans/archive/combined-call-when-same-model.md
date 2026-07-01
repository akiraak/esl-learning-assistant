# OCRモデルと翻訳モデルが同じ場合は1回の呼び出しにまとめる

## 目的・背景

[[translate-model-selection]]でOCRと翻訳を2回の独立したAPI呼び出しに分割したが、翻訳ステップの
入力にOCR結果を再度渡す分だけ余分なトークンコストが発生する。OCRモデルと翻訳モデルが同じ設定
（`ANTHROPIC_MODEL` === `ANTHROPIC_TRANSLATE_MODEL`）の場合は、そのコスト差分に意味が無い
（どうせ同じモデルで2回課金されるだけ）ので、元の設計どおり1回の呼び出し（画像→ocrText+translatedText
を同時取得）にまとめる。モデルが異なる場合は引き続き2回に分けて呼び出す。

## 対応方針

### Step 1: `ocrTranslate.ts` に共通の構造化出力呼び出しヘルパーを作る

- `callStructured(model, schema, content)` を新設し、`messages.create` の呼び出しと
  レスポンスからのJSON抽出・トークン数取得を共通化する。
- `effort: "low"` はHaikuモデルが非対応（前回検証済み: `This model does not support the effort parameter.`）
  なため、モデル名に`haiku`を含む場合は`output_config`から`effort`を省略する。

### Step 2: モデルが同じ場合は1回の統合呼び出し、異なる場合は2回に分岐する

- `COMBINED_SCHEMA`（ocrText + translatedText、元の統合設計と同じ内容）を追加する。
- `ocrAndTranslate()` で `config.ocrModel === config.translateModel` の場合は
  画像を渡す1回の呼び出しでocrText/translatedTextを同時取得する（`combinedOcrAndTranslate`）。
- 異なる場合は既存の`ocrImage`→`translateText`の2回呼び出しを維持する。
- どちらの経路でも戻り値の型（`OcrTranslateResult`）は変えない。統合呼び出し時は
  `translateModel`に同じモデル名を設定しつつ`translateInputTokens`/`translateOutputTokens`は
  `0`にし、トークン・コストはすべて`ocr*`側に計上する（`index.ts`のコスト計算はそのままで
  合計が正しくなる）。

### Step 3: adminの表示で統合呼び出しであることが分かるようにする

- `backend/src/admin.ts` で `translate_model === ocr_model` かつ`translate_input_tokens === 0`
  の場合（＝統合呼び出しの成功ログ）は、翻訳欄に「OCR呼び出しに統合（追加コストなし）」のように
  表示し、2回呼び出しで翻訳が0トークンだったかのような誤解を避ける。

## 影響範囲

- `backend/src/ocrTranslate.ts`
- `backend/src/admin.ts`

## テスト方針

- `npm run build` でビルド確認。
- デフォルト設定（OCR=Sonnet 5 / 翻訳=Haiku、モデルが異なる）で実画像を投げ、
  従来通り2回呼び出し（翻訳ログにHaikuの実トークン数が入る）になることを確認する。
- `ANTHROPIC_TRANSLATE_MODEL=claude-sonnet-5` で一時的に両方Sonnet 5にして再起動し、
  同じ画像を投げて1回の統合呼び出しになること（`translate_input_tokens`が0、
  `ocr_input_tokens`/`ocr_output_tokens`が統合呼び出し相当の値になること）を確認後、
  設定を既定（Haiku翻訳）に戻す。
- `/admin`で統合呼び出しのログが分かりやすく表示されることを確認する。
