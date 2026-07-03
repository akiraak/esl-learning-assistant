# 単語詳細に意味が直感的に分かるイラストをAI生成して表示する

## 目的・背景

単語詳細画面（iOS `WordDetailView`）には現在、AI生成の単語情報（意味・例文・発音など）が
テキストで表示されるのみ。意味を直感的に理解できるよう、単語の中心的な意味を表すイラストを
AIで生成して単語詳細に表示する。

生成には OpenAI の画像生成モデル **GPT Image 2** を利用する（新規に `OPENAI_API_KEY` が必要）。
バックエンドの実装パターンは Gemini TTS
（`backend/src/tts.ts` + `/api/tts` + `tts_audio` テーブル + `data/tts/` 保存）を踏襲する。

多義語の扱い: 自動生成は第1義（最頻出の意味）の1枚のみとする。ただしキャッシュキーと
テーブルに `sense_index` を含めておき、将来「意味ごとにタップで生成」に拡張できるようにする。

## 対応方針

### Phase 1: バックエンド（生成API・保存・料金記録）

- `backend/src/illustration.ts`（新規）
  - `tts.ts` と同様に raw `fetch` で OpenAI Images API
    （`https://api.openai.com/v1/images/generations`、モデルは GPT Image 2。
    正確なモデルIDは実装時に公式ドキュメントで確認する）を呼び、
    base64 レスポンスから画像バイト列を取り出す
  - プロンプトは「単語 + 意味（`WordInfo` の該当義の定義/訳語）+ 例文」から
    英語で組み立てる（プロンプト例は後述）
- `backend/src/db.ts`
  - `word_illustrations` テーブルを追加（`tts_audio` を踏襲）:
    `id, word, target_language, sense_index, prompt, model, key_hash (UNIQUE), filename,
    byte_size, cost_usd, created_at`
  - キャッシュキーは `sha256("model|word|target_language|sense_index")`
- `backend/src/config.ts`: `OPENAI_API_KEY` と
  `illustrationsDir`（`backend/data/illustrations/`）を追加、`.env.example` にも追記
- `backend/src/index.ts`
  - `POST /api/word-illustration`（`X-API-Secret` 必須）を追加
    - リクエスト: `{ word, targetLanguage, senseIndex? }`（省略時は第1義）
    - キャッシュヒット時は保存済み PNG をそのまま返す（`image/png`）
    - ミス時は `words.word_info_json` から該当義の意味・例文を取得
      （無ければ単語のみで生成）→ 画像生成 → `data/illustrations/<hash>.png` 保存 →
      メタデータ + `cost_usd` を記録
- `backend/src/pricing.ts`
  - GPT Image 2 の料金を追加。画像モデルはトークン単価ではなく
    「1枚あたり（品質・サイズ別）」の固定額なので、`estimateCostUsd` とは別に
    画像用の単価テーブルを設ける（実装時に公式料金を確認して単価を設定する）
  - `pricingSync.ts` による自動更新は対象外とし、手動単価で `/admin/pricing` に表示する

#### プロンプトのテンプレート（英語で生成、日本語版は参考）

英語（実際に API へ送るもの）:

> A simple flat-style educational illustration that intuitively conveys the meaning of
> the English word "{word}" ({definition}). Depict a single clear scene based on this
> example: "{example_sentence}". Clean vector art, soft colors, plain light background.
> Absolutely no text, letters, or numbers anywhere in the image.

日本語（同内容の参考訳）:

> 英単語「{word}」（意味: {definition}）の意味が直感的に伝わる、シンプルでフラットな
> 教育用イラスト。例文「{example_sentence}」の場面を1つの分かりやすい構図で描く。
> クリーンなベクター風、柔らかい配色、無地の明るい背景。
> 画像内に文字・アルファベット・数字は一切入れない。

### Phase 2: 管理画面（イラスト一覧・再生成・削除）

- `backend/src/admin.ts`
  - `NAV_ITEMS` / `NavSection` に「単語イラスト」を追加
  - `GET /admin/illustrations`: 一覧ページ（サムネイル・単語・モデル・コスト・生成日時）
    — `/admin/tts` 一覧を踏襲
  - `GET /admin/illustrations/:id/image`: `res.sendFile` で画像配信
  - `POST /admin/illustrations/:id/delete` / `:id/regenerate`: 削除・再生成
    （TTS の delete/regenerate ハンドラを踏襲）

### Phase 3: iOS（単語詳細への表示・ローカルキャッシュ）

- `Sources/Services/WordIllustrationStore.swift`（新規）
  - `TTSAudioStore` を踏襲: Application Support `/illustrations/<key>.png` に保存、
    サーバーと同じキー規則でローカルキャッシュ
- `Sources/Services/BackendAPI.swift` 経由で `POST /api/word-illustration` を呼ぶ
  サービスを追加（`RemoteWordInfoService` と同様の形）
- `Sources/Views/WordDetailView.swift`
  - `WordAIInfoSections` の先頭（Meanings の上）にイラストセクションを追加
  - ローカルキャッシュがあれば即表示、無ければ生成ボタン（またはAI情報生成済みなら
    自動取得）→ スピナー → 表示、の `TTSButton` と同様の状態遷移
- SwiftData `Word` モデルへのフィールド追加は行わない
  （画像はファイルキャッシュで管理し、モデル変更によるマイグレーションを避ける）

## 影響範囲

- 変更: `backend/src/db.ts`, `backend/src/config.ts`, `backend/.env.example`,
  `backend/src/index.ts`, `backend/src/pricing.ts`, `backend/src/admin.ts`,
  iOS側 `WordDetailView.swift`, `BackendAPI.swift`（利用のみなら変更なし）
- 新規: `backend/src/illustration.ts`, `backend/data/illustrations/`（実行時生成）,
  iOS側 `WordIllustrationStore.swift` ほかサービス1件
- DB: `word_illustrations` テーブル追加（既存テーブルの変更なし）

## テスト方針

- バックエンド: `tsc` ビルド確認。`curl` で `POST /api/word-illustration` が
  1回目=生成して PNG を返す / 2回目=キャッシュヒット（DB件数が増えない）ことを確認。
  `cost_usd` が記録され `/admin/pricing` の単価と整合することを確認
- 管理画面: `/admin/illustrations` で一覧表示・画像表示・削除・再生成を手動確認
- iOS: `xcodebuild` でシミュレータ向けビルド成功を確認。
  シミュレータで単語詳細を開きイラスト生成→表示→再表示時にローカルキャッシュが
  使われることを確認
- イラストの品質（意味の分かりやすさ）はユーザー側で数単語を見て評価を依頼し、
  必要ならプロンプトを調整する
