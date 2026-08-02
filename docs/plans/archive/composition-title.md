# 作文にタイトルを付ける（管理画面）

## 目的・背景

`/admin/writing` の一覧は本文の先頭 70 文字をそのまま行の見出しに使っている
（`compositionPreview`）。書き溜めるほど「どれがどの記事か」が本文の書き出しだけでは
判別しづらく、探すのに開いて確かめる必要がある。

TODO の元項目:

- 管理画面作文の記事タイトル
  - 編集画面の上部に入力欄と本文からの生成ボタン（適度な短さにする）
  - 空欄なら本文の最初を記事一覧に表示（現状と同じ）

## 現状（as-is）

- `compositions` テーブルに持つのは `english_text` / `japanese_text` / `explanation_language` と日時のみ
  （`backend/src/db.ts:135`）。タイトルの置き場が無い。
- 一覧 `/admin/writing` は `compositionPreview()` で本文（無ければ意図）の先頭を 1 行に丸めて表示
  （`backend/src/admin.ts:1091`）。
- 執筆画面 `/admin/writing/:id` は「細いツールバー + 罫線紙の本文入力欄 + 右の AI チャット」だけの
  単独ページ（`backend/src/compositionView.ts:165`）。本文は 1.5 秒デバウンスで
  `POST /admin/writing/:id/save` へ自動保存する。
- 読書用ページ `/admin/writing/:id/read` の見出しも `compositionPreview()` から作っている
  （`backend/src/admin.ts:1432`）。

## 方針（to-be）

**`compositions.title` を追加し、執筆画面の紙の一番上（本文の上）で編集する。空欄なら
これまでどおり本文の先頭を一覧・読書ページの見出しに使う（＝挙動は現状のまま）。**

決定事項:

1. **タイトルは任意** — 空欄が既定。空欄時のフォールバックは現行の `compositionPreview()` をそのまま使う。
2. **入力欄は紙の上に置く**（ツールバーではなく `.sheet` の内側の先頭）。紙に記事の題を書く体裁に揃える。
   罫線と本文行のズレを防ぐため、タイトル行の高さは行送り `PAPER_LINE_HEIGHT_PX` の整数倍（2 行分）に固定する。
3. **生成は本文からの AI 生成ボタン 1 つ**（「本文から生成」）。押すと本文を保存してから生成し、
   入力欄へ入れて保存まで済ませる。上書き確認は出さない（取り消したければ手で書き直せる）。
4. **モデルは haiku**（`ANTHROPIC_WRITING_TITLE_MODEL`、既定 `claude-haiku-4-5`）。
   短い1タスクなので単語正規化（`wordNormalizeModel`）と同じ扱いにする。
5. **AI 呼び出しは必ずログに残す** — `composition_title_requests` を追加し、`/admin/usage` に
   機能キー `writing-title`（表示名「作文タイトル」）として集計する。ハウスの規約
   （AI 呼び出しは 1 件 1 行の課金ログを残す）に合わせる。

「適度な短さ」の定義:

- プロンプトで **英語・5〜8 語程度・末尾のピリオド無し** を要求する（本文が英作文なのでタイトルも英語）。
- サーバ側で `sanitizeCompositionTitle()` を通し、改行・囲みの引用符・前後空白を落とし、
  `COMPOSITION_TITLE_MAX_LENGTH = 120` 文字で切る（手入力にも同じ上限を当てる）。

## 影響範囲

| 対象 | 変更 |
| --- | --- |
| `backend/src/db.ts` | `compositions.title` 列（既存 DB は `ALTER TABLE` で後方互換移行）・`updateCompositionTitle()`・`composition_title_requests` テーブルとログ関数・usage 集計への追加 |
| `backend/src/config.ts` | `writingTitleModel` を追加 |
| `backend/src/compositionTitle.ts`（新規） | タイトル生成（プロンプト・`callStructured`）と `sanitizeCompositionTitle()` |
| `backend/src/compositionView.ts` | 執筆画面にタイトル入力欄と生成ボタン・保存/生成の JS。一覧見出しを決める `compositionListTitle()` を追加 |
| `backend/src/admin.ts` | 一覧の見出しをタイトル優先に・`/save` で `title` を受ける・`POST /admin/writing/:id/title` を追加・読書ページの見出しをタイトル優先に・usage の表示名 |
| `backend/test/` | `compositions.test.ts`（列と更新）/ `compositionView.test.ts`（見出しの決定と描画）/ `compositionTitle.test.ts`（整形の純関数）|

## Phase 1: 保存できるようにする

**Step 1-1. スキーマ**

```sql
ALTER TABLE compositions ADD COLUMN title TEXT NOT NULL DEFAULT '';
```

既存 DB のために `PRAGMA table_info(compositions)` で列の有無を見てから流す
（`requests` / `word_info_requests` と同じ後方互換の書き方）。

**Step 1-2. CRUD**

- `updateCompositionTitle(id, title): boolean` — `updated_at` も進める。本文の保存とは別 UPDATE にして、
  どちらか片方だけの保存要求（自動保存 / 生成）でも他方を巻き戻さないようにする。
- `CompositionRow` / `CompositionListRow` に `title` を足す（一覧の SQL は `SELECT c.*` なので変更不要）。

**Step 1-3. 保存 API**

`POST /admin/writing/:id/save` に任意フィールド `title` を追加する（省略時は現状維持）。
`englishText` と同様に長さを検証し、超過は 400。

## Phase 2: タイトル生成

**Step 2-1. `compositionTitle.ts`**

- `sanitizeCompositionTitle(raw): string` — 改行を空白へ、連続空白を 1 つへ、前後の `"` `'` `「」` を剥がし、
  末尾のピリオドを落とし、`COMPOSITION_TITLE_MAX_LENGTH` で切る（純関数・テスト対象）。
- `generateCompositionTitle(text)` — `callStructured<{ title: string }>` で `{ title }` を受け、
  `sanitizeCompositionTitle` を通して返す。トークン数・モデルも返す。

**Step 2-2. `POST /admin/writing/:id/title`**

保存済み本文からタイトルを作り、`compositions.title` に入れて `{ title }` を返す
（画面側は送信前に自動保存を確定させてから叩く＝チャットと同じ約束）。
本文が空なら 400（「本文がまだ空です」）。成功・失敗のどちらも `composition_title_requests` に 1 行残す。

## Phase 3: 画面

**Step 3-1. 執筆画面（`/admin/writing/:id`）**

- `.sheet` の先頭に `.title-row`（高さ = 行送り × 2）を置き、`input.title`（serif・24px）と
  「本文から生成」ボタンを並べる。プレースホルダで空欄時の挙動（一覧に本文の先頭が出ること）を示す。
- 本文入力欄と綴りの下敷きは `.paper-area`（`position: relative`）で包み直し、下敷きの座標を
  `.sheet` 基準から本文ブロック基準へ変える（タイトル行が入っても赤線が字の下からずれないようにする）。
- タイトルは本文と同じデバウンス自動保存に相乗りする（`/save` に `title` を含める）。
- 生成ボタン: 押下 → 本文を保存 → `POST /title` → 入力欄へ反映。実行中は disabled。
  失敗はツールバーの状態表示に出す（バナーを増やさない）。
- 印刷時は生成ボタンを隠し、タイトルは紙の見出しとして残す。

**Step 3-2. 一覧（`/admin/writing`）**

`compositionListTitle({ title, englishText, japaneseText })` を新設し、タイトルがあればそれ、
無ければ現行の `compositionPreview()` を返す。行の見出しをこれに差し替える
（本文の 2 行目に出している意図のプレビューはそのまま）。

**Step 3-3. 読書用ページ（`/admin/writing/:id/read`）**

見出しもタイトル優先にする（空欄なら現行どおり最終添削文からのプレビュー）。

## テスト方針

- `backend/test/compositionTitle.test.ts`: 整形（改行・引用符・末尾ピリオド・長さ）の純関数を検証。
- `backend/test/compositions.test.ts`: 新規作文のタイトルが空文字であること、`updateCompositionTitle` が
  更新し `updated_at` を進めること、存在しない ID で false になること。
- `backend/test/compositionView.test.ts`: `compositionListTitle` の優先順位、執筆画面 HTML に
  タイトルの値・生成ボタン・POST 先が出ること、`"` や `<` を含むタイトルがエスケープされること。
- 手動: 新規作文 → 本文を書く → 生成ボタン → 一覧の見出しが変わること、タイトルを消すと本文の先頭に戻ること、
  `/admin/usage` に「作文タイトル」が 1 回分計上されること。

## 将来の拡張候補（今回はやらない）

- タイトルでの検索・絞り込み。
- 本文を書き終えた時点での自動命名（保存のたびに黙って AI を呼ぶのはコストが読めないため見送り）。
