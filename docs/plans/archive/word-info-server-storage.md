# 単語データのサーバ保存（キャッシュ化＋管理画面）

## 目的・背景

現状の `POST /api/word-info`（`backend/src/index.ts:161`）はリクエストのたびに Claude API で
単語情報を生成しており、サーバ側には `word_info_requests` テーブルへの**ログ**しか残らない。
生成結果の正式な保存先は iOS 側 SwiftData（`Word.aiInfo`）のみ。

そのため:

- 同じ単語を複数回登録（別クラス・再インストール・デバッグ削除後など）すると毎回生成コストがかかる
- サーバ側に「どの単語がどんな内容で生成済みか」を管理する手段がない

本タスクでは単語情報をサーバに永続化し、

1. アプリから取得リクエストが来たとき**保存済みならそれを返し、なければAI生成して保存**する
2. **再生成リクエスト**が来たときは作成しなおして保存を更新する
3. サーバ管理画面に**単語一覧**を作り、**削除・再生成**を可能にする

## 対応方針

### Phase 1: backend — `words` テーブルとキャッシュ返却・再生成

`backend/src/db.ts` に単語情報の正式な保存テーブルを新設する
（`word_info_requests` は従来どおり通信ログとして温存し、役割を分ける）:

```sql
CREATE TABLE IF NOT EXISTS words (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word TEXT NOT NULL,               -- 正規化済み見出し語（trim + 小文字化）
  target_language TEXT NOT NULL,
  word_info_json TEXT NOT NULL,     -- WordInfo のJSON
  model TEXT NOT NULL,              -- 生成に使ったモデル
  context TEXT,                     -- 最後の生成に使った文脈（管理画面からの再生成で再利用）
  user_translation TEXT,            -- 同上
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  generation_count INTEGER NOT NULL DEFAULT 1,
  UNIQUE(word, target_language)
);
```

- キャッシュキーは `(正規化した word, targetLanguage)`。正規化は `trim + toLowerCase`
  （"Apple" と "apple" は同一エントリ。固有名詞の大文字小文字は区別しない割り切り）
- `POST /api/word-info` のリクエストに `regenerate?: boolean`（省略時 false）を追加
  - `regenerate` でない & 保存済み → Claude API を呼ばず保存内容を返す
  - 未保存 or `regenerate: true` → 従来どおり `generateWordInfo()` で生成し、
    `INSERT ... ON CONFLICT(word, target_language) DO UPDATE` で保存
    （同時リクエストが二重生成した場合は後勝ちで確定。実害がないため許容する）
- レスポンスは `{ wordInfo, model, cached }` に拡張（`cached: true` = 保存済み返却。
  iOS の `WordInfoResponse` デコードは追加フィールドを無視するため後方互換）
- ログ: `word_info_requests` に `cache_hit INTEGER NOT NULL DEFAULT 0` カラムを追加
  （既存DBは `PRAGMA table_info` + `ALTER TABLE` の既存パターンで後方互換マイグレーション）。
  キャッシュ返却時もコスト0・`cache_hit=1` で記録し、管理画面のログで利用状況を追えるようにする

### Phase 2: 管理画面 — 単語一覧・詳細（削除・再生成）

`backend/src/admin.ts` にナビ「単語一覧」を追加（`navLinks` を3項目に拡張）:

- `GET /admin/words`: 保存済み単語の一覧テーブル
  （id / 見出し語 / 言語 / 先頭語義プレビュー / モデル / 生成回数 / 作成・更新日時 / 詳細リンク）
- `GET /admin/words/:id`: 詳細ページ。既存の `renderWordInfoBlock`（`admin.ts:274`）を流用して
  生成内容を表示し、操作ボタンを置く
  - **削除**: `POST /admin/words/:id/delete` → 行削除して一覧へリダイレクト
    （form + confirm ダイアログ。削除後にアプリから同じ単語のリクエストが来れば再生成される）
  - **再生成**: `POST /admin/words/:id/regenerate` → 保存済みの `context` / `user_translation` を
    使って `generateWordInfo()` を再実行し、行を更新して詳細へリダイレクト
    （`word_info_requests` にもログを残す）
- `/admin` は Cloudflare Access（エッジ）保護・ローカル開発用のため、CSRF対策は追加しない
  （既存方針を踏襲）

### Phase 3: iOS — 再生成フラグの送信

- `WordInfoService` プロトコル / `RemoteWordInfoService.fetchWordInfo` に
  `regenerate: Bool` 引数を追加してリクエストボディに含める
- `WordAIInfoGenerator.generate(for:regenerate:)` に引き回す。呼び出し元:
  - `WordAddView` 登録時・`WordsView` 一括生成・`WordDetailView` の「再試行」（failed時）→ `false`
    （サーバ保存があればそれを受け取る＝高速・ゼロコスト）
  - `WordDetailView` の「AI情報を再生成」メニュー → `true`（サーバ側も作りなおす）
- `WordInfoResponse` に `let cached: Bool?` を追加（表示には使わないが将来のデバッグ用）

## 影響範囲

- backend: `src/db.ts`（`words` テーブル・CRUD関数、`word_info_requests` の `cache_hit` 追加）、
  `src/index.ts`（`/api/word-info` のキャッシュ分岐・`regenerate` 受付）、
  `src/admin.ts`（単語一覧・詳細・削除・再生成、ナビ拡張）
- iOS: `Sources/Services/RemoteWordInfoService.swift`、`Sources/Support/WordAIInfoGenerator.swift`、
  `Sources/Views/WordDetailView.swift`（再生成メニューの引数のみ）
- DB: 新テーブル `words`、既存 `word_info_requests` へのカラム追加（既存ログは保持）

## テスト方針

- backend（`tsc` ビルド後、curl で実キー確認）:
  - 未保存の単語 → 生成されレスポンスに `cached: false`、`words` に1行入ること
  - 同じ単語をもう一度 → `cached: true` で高速に返り、`words` の行が増えないこと
  - `regenerate: true` → 再生成され `updated_at` / `generation_count` が更新されること
  - 大文字違い（"Apple" / "apple"）が同一キャッシュに当たること
- 管理画面: 一覧表示・詳細表示・削除→一覧から消える・再生成→内容と更新日時が変わることを
  ブラウザで手動確認。ログ一覧に `cache_hit` の区別が出ること
- iOS: `xcodebuild` ビルド確認。`WordInfoService` モックを使った既存ユニットテストの
  シグネチャ追従（regenerate引き回しのステータス遷移が壊れないこと）
