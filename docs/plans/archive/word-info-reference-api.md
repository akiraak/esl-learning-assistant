# 単語情報の参照 API（他アプリからの読み取り専用アクセス）

## 目的・背景

- `words` テーブルには iOS アプリで登録した単語の生成済み単語情報（`word_info_json`）が蓄積されている。
- 既存の `POST /api/word-info` は「生成（キャッシュミス時は Claude API を呼び課金される）」用であり、
  他のアプリから安全に参照する用途には向かない。
- 他のアプリ（別クライアント・スクリプト等）から保存済みの単語情報を **読み取り専用** で
  参照できる API を追加する。AI は一切呼ばない（課金・書き込みが発生しない）。

## 対応方針

エンドポイントを 2 つ追加する。いずれも既存 `/api` ミドルウェアの `X-API-Secret` 認証をそのまま使う。

### 1. `GET /api/words` — 一覧・検索

クエリパラメータ（すべて省略可）:

| param | 説明 |
| --- | --- |
| `targetLanguage` | 完全一致フィルタ（例: `ja`） |
| `q` | 単語の部分一致検索（大文字小文字は正規化キーに従い区別なし） |
| `updatedSince` | ISO 8601。これ以降に更新されたエントリのみ（他アプリの差分同期用） |
| `limit` | 1〜500、デフォルト 100 |
| `offset` | 0〜、デフォルト 0 |
| `includeInfo` | `true` で各エントリに `wordInfo` 全体を含める（一括エクスポート用） |

レスポンス: `{ total, limit, offset, words: [...] }`。
各要素は `word` / `targetLanguage` / `createdAt` / `updatedAt` に加え、`word_info_json` から
取り出したサマリ（第1義の `meaning` / `partOfSpeech`、`cefrLevel`）を含める。
`word_info_json` が壊れている行はサマリ null で返す（エラーにしない）。

### 2. `GET /api/words/:word` — 1 語の詳細

- `targetLanguage` クエリ必須（`words` の一意キーが `(word, target_language)` のため。既存 API と同じ流儀）。
- キーは既存の `normalizeWordKey`（trim + 小文字化）で正規化して引く。熟語は URL エンコード（`look%20up`）。
- 見つかれば `{ word, targetLanguage, wordInfo, model, createdAt, updatedAt, generationCount }`、
  無ければ 404 `{ error: "word not found" }`。生成は行わない（生成したければ既存 `POST /api/word-info`）。

## 影響範囲

- `backend/src/db.ts`: 検索用 `queryStoredWords()` を追加（既存関数は変更しない）。
- `backend/src/wordsApi.ts`（新規）: クエリパラメータの検証・レスポンス整形の純粋ロジック
  （HTTP から分離して単体テスト可能にする）。
- `backend/src/index.ts`: ルート 2 本を追加。既存エンドポイントの変更なし。
- iOS 側・管理画面の変更なし。DB スキーマ変更なし。

## テスト方針

- `backend/test/wordsApi.test.ts`（新規）: パラメータ検証（limit/offset/updatedSince の境界、
  不正値の 400 相当）、サマリ整形（正常 JSON / 壊れた JSON）を単体テスト。
- `npm test` 全体がグリーンであること。
- `npm run build` 後、ローカルサーバに対して curl で一覧・詳細・404・認証エラー（401）を実地確認。

## Phase / Step

- [x] Phase 1: `db.ts` に `queryStoredWords()` を追加
- [x] Phase 2: `wordsApi.ts`（検証・整形ロジック）と `index.ts` のルート追加
- [x] Phase 3: 単体テスト追加＋ビルド・curl での実地確認
