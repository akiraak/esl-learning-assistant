# 執筆画面の紙をタブ化して1作文に複数ページを持たせる（＋添削機能の削除）

## 目的・背景

`/admin/writing/:id` の紙は本文が 1 枚きりで、下書き・清書・メモのように書き分けたいときは
作文そのものを分けるしかない。関連する文章がバラバラの作文として一覧に並び、行き来も一覧経由になる。

TODO の元項目:

- 管理画面作文の編集画面左の紙の上部をタブ化して複数ページを持てるようにする
  タブ名を編集可能にする

あわせて、使っていない添削（Review）機能を削除して構造を単純にする。ページ化にあたって
「ラウンドはどのページに属するのか」を決めずに済ませられる（＝設計をページ単体に集中できる）。

## 現状（as-is）

- `compositions` は 1 行＝1 作文で、本文は `english_text` 1 カラム（`backend/src/db.ts:135`）。
  タイトル `title` も 1 作文に 1 つ（`docs/plans/archive/composition-title.md`）。
- 執筆画面 `/admin/writing/:id`（`backend/src/admin.ts:1171`）は
  「ツールバー ＋ タイトルカード ＋ 罫線紙 1 枚 ＋ 右の AI チャット」の単独ページ
  （`renderCompositionEditorPageHtml()` / `backend/src/compositionView.ts:179`）。
  本文は 1.5 秒デバウンスで `POST /admin/writing/:id/save` へ自動保存（`admin.ts:1263`）。
- スペルチェックは本文全体を `POST /admin/writing/:id/spellcheck` に投げて赤い波線を引く（`admin.ts:1367`）。
- チャットは 1 作文に 1 スレッド（`composition_chat_messages`、`db.ts:194`）。質問時は
  `composition.english_text` をプロンプトに同梱する（`admin.ts:1237`）。
- 添削は `POST /admin/writing/:id/review`（`admin.ts:1421`）が `composition_rounds` に積み、
  一覧の状態バッジ・ラウンド数・「読む →」（`/admin/writing/:id/read`、`admin.ts:1510`）が
  それを参照する。実運用ではチャットに置き換わっていて使っていない。
- `POST /api/writing-feedback`（`backend/src/index.ts:775`）も同じ添削生成を公開しているが、
  iOS 側は `Composition.swift` にレスポンス型の定義があるだけで呼び出しは無い。

## 方針（to-be）

**`composition_pages` を追加し、本文の持ち主を作文からページへ移す。執筆画面の紙の上に
タブを並べ、タブ名（＝ページ名）はその場で編集できる。AI に渡す本文は選択中のページ、
チャット履歴は作文で 1 本のまま。添削（Review）機能は削除する。**

決定事項（ユーザー確認済み）:

1. **1 作文の中に複数ページ** — タブはページ。記事タイトル（`compositions.title`）は作文に 1 つのままで、
   タイトルカードはタブ列の上に残す。一覧 `/admin/writing` の単位も作文のまま。
2. **AI に渡す本文はページ単位** — チャットもスペルチェックもタイトル生成も、
   選択中のページの本文だけを対象にする（全ページ連結はしない）。
3. **チャット履歴は作文で 1 本** — `composition_chat_messages` は今のまま。タブを切り替えても
   会話は途切れない。どのページについての質問かは、その時点の選択中ページの本文をプロンプトに
   同梱することで表す。
4. **添削機能は削除** — Review ボタン・`composition_rounds`・読書ページ・一覧の状態バッジ /
   ラウンド数を落とす。`/api/writing-feedback` と `writing_feedback_requests`（添削ログ画面）も
   同時に削除する（iOS からの呼び出しが無いことを確認済み）。
5. **既存作文は 1 ページに移行** — マイグレーションで各 `compositions` 行から
   ページを 1 枚作り、`english_text` を移す。移行後の既定のページ名は空（表示は「ページ 1」）。

補助的な決定:

- **ページ名は任意・空でよい** — 空なら `ページ N`（N は並び順）をタブに出す。上限 40 文字。
- **並び順は `position` の整数**（1 始まり）。ドラッグ並べ替えは今回のスコープ外（Phase 5 の候補）。
- **最低 1 ページ** — 最後の 1 枚は削除できない（削除ボタンを無効化）。
- **選択中のタブはサーバに持たせず**、ブラウザの `localStorage`（キーに作文 ID を含める）に覚える。
  無い / 消えたページを指していたら先頭ページにフォールバックする。
- **1 作文あたりのページ数は 20 枚まで**（それ以上はタブが並ばない。超えたら「＋」を無効化）。

## データモデル

```sql
CREATE TABLE composition_pages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  composition_id INTEGER NOT NULL REFERENCES compositions(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,          -- 1 始まりのタブの並び順
  name TEXT NOT NULL DEFAULT '',      -- タブ名。空なら「ページ N」を表示
  english_text TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(composition_id, position)
);
CREATE INDEX idx_composition_pages_composition ON composition_pages(composition_id, position);
```

- `compositions.english_text` は移行後も**残す**（`japanese_text` と同じく一覧のプレビューや
  過去データの保険に使う）。書き込みは止め、ページ 1 の本文のミラーとして更新する。
  ※ 一覧のプレビューを「先頭ページの本文」から引き直せば落とせるので、Phase 5 で判断する。
- `better-sqlite3` は `PRAGMA foreign_keys = OFF` 既定のため、`deleteComposition()` の
  トランザクションにページの削除を足す（`db.ts:905` と同じ流儀）。
- `position` の振り直し（追加・削除）はトランザクション内で行い、`UNIQUE` 制約を壊さない。

## 画面（執筆画面の左ペイン）

```
┌──────────────────────────────────────┐
│ ← 作文一覧            保存済み  削除  │  ツールバー（現状のまま）
├──────────────────────────────────────┤
│ ┌──────────────────────────────────┐ │
│ │ A Visit to Grandma      本文から生成│ │  タイトルカード（作文に1つ・現状のまま）
│ └──────────────────────────────────┘ │
│ ┌──────┐╥──────╥──────╥              │  タブ列（新規）
│ │ 下書き│║ 清書 ║ メモ ║  ＋          │  選択中＝紙と同色・下辺なし
│ │      └╨──────╨──────╨────────────┐ │  非選択＝一段沈んだ色・境界線あり
│ │ Last weekend I visited my ...    │ │  ↑ここから下が同じ1枚の紙（影も一体）
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

選択中のタブは紙の一部（同じ地色・境界線なし）で、非選択のタブだけが後ろに重なった別紙として見える。
タブ列と紙は同じ影を共有し、全体で 1 つのかたまりになる。

- **タブは紙と一体にする**（別のバーとして分離させない）。ノートに貼った見出しインデックスの体裁で、
  タブ列と紙は 1 つのかたまりとして扱う。
  - タブ列と `.sheet` の間に隙間・境界線を置かない（`margin-bottom: 0`）。影はタブ列と紙をまとめて
    1 つ落とす（タブ列と紙を `.paper-stack` のような親で包み、影はその親に付ける。
    子の `.sheet` 側の影は外す）。
  - **選択中のタブは紙そのもの** — 地色は紙と同じ `#FFFDF7`、上と左右だけ角丸（6px 6px 0 0）、
    下辺の線は消して紙へつながる。タブと紙の境目が見えないのが正しい状態。
  - **非選択のタブは紙の下に重なった別紙** — 一段沈んだ `#F5EFE1`、下辺に紙との境界線
    `1px solid #DFDACB` を引き、高さを 2px 低くして奥に見せる。ホバーで紙の色に近づける。
  - タブの文字は紙と同じセリフ体（本文・タイトルと同じフォントスタック）にして、UI 部品ではなく
    紙の一部に見せる。左右の位置は `--pad-x` に合わせず、タブ列は紙の左端から始める。
  - タイトルカードとの間だけは余白（12px）を空け、「別の紙が上に載っている」関係を保つ。
- **タブ名の編集**: タブをダブルクリック（またはフォーカス中に F2 / Enter）でその場が入力欄になり、
  Enter か blur で確定、Esc で取り消し。確定時に `PATCH` 相当の保存を投げる。
- **追加**: タブ列の右端の「＋」。押すと末尾に空ページを作って選択する。
- **削除**: 選択中タブの右に出る小さな「×」。本文が空でなければ確認ダイアログを出す。
- **切り替え時の約束**: 現在ページの自動保存を確定（`flush`）してから、次のページの本文と
  スペルチェック結果を差し替える。保存前に切り替わって本文が混ざる事故を防ぐ。
- 狭い画面ではタブ列を横スクロールにする（`overflow-x: auto`、折り返さない）。

## API

| メソッド・パス | 役割 |
| --- | --- |
| `POST /admin/writing/:id/pages` | ページ追加。`{ name? }` → `{ page }` |
| `POST /admin/writing/:id/pages/:pageId/rename` | タブ名の変更。`{ name }` → `{ name }`（整形後） |
| `POST /admin/writing/:id/pages/:pageId/delete` | ページ削除（最後の 1 枚は 409） |
| `POST /admin/writing/:id/save` | 既存。`{ pageId, englishText, title? }` を受けてページ本文を保存 |
| `POST /admin/writing/:id/spellcheck` | 既存。`{ pageId }` を足し、そのページの本文を検査 |
| `POST /admin/writing/:id/chat` | 既存。`{ message, pageId }`。プロンプトに載せるのは当該ページの本文 |
| `POST /admin/writing/:id/title` | 既存。`{ pageId }` を足し、そのページの本文からタイトルを作る |

- `pageId` は必須（省略時は 400）。ただし移行直後の互換のため、`pageId` 省略なら
  先頭ページにフォールバックする実装にしてもよい（Phase 2 で判断）。
- ページ名の整形は `sanitizeCompositionTitle()` と同じ考え方の
  `sanitizePageName()`（改行→空白、前後の空白落とし、40 文字で切る）を新設する。

## Phase / Step

### Phase 1: 添削機能の削除

- `POST /admin/writing/:id/review`、`/admin/writing/:id/read`、`/admin/writing-feedback`（一覧・詳細）、
  `POST /api/writing-feedback` を削除
- `writingFeedback.ts` / `writingFeedbackRunner.ts` / `composition_rounds` /
  `writing_feedback_requests` と、一覧の状態バッジ・ラウンド数・「読む →」導線を削除
- `compositionStatus()` / `canReviewComposition()` / `draftMatchesLastRound()` と
  `renderCompositionReadPageHtml()`、`/admin/usage` の「作文添削」集計、
  `config.writingFeedbackModel` を削除
- 既存テーブルは `DROP TABLE` せず残置（過去データを消さない。読み書きだけ止める）
- テスト: `writingFeedback.test.ts` を削除、`compositions.test.ts` / `compositionView.test.ts` /
  `printView.test.ts` の添削依存を落とす

### Phase 2: ページのデータモデルと移行

- `composition_pages` を作成し、起動時に「ページが 0 件の作文」へ 1 枚作って
  `english_text` を移すマイグレーションを入れる（`compositions.title` の `ALTER TABLE` と同じ流儀）
- `listCompositionPages()` / `getCompositionPage()` / `insertCompositionPage()` /
  `updateCompositionPageText()` / `renameCompositionPage()` / `deleteCompositionPage()` を `db.ts` に追加
- `deleteComposition()` のトランザクションにページ削除を追加
- テスト: 移行（0 件→1 枚）、追加・削除時の `position` 振り直し、最後の 1 枚は削除不可

### Phase 3: 執筆画面のタブ UI

- `CompositionEditorPage` に `pages: { id, name, position }[]` と `activePageId` を追加し、
  タブ列をタイトルカードと紙の間に描く
- タブ列と `.sheet` を `.paper-stack` で包み、影は親にまとめて 1 つだけ落とす（紙とタブを一体に見せる）
- タブの切り替え・追加・削除・その場リネームのスクリプトと CSS
  （選択中タブは紙と同じ地色で下辺なし＝紙の一部、非選択だけ沈めて後ろの紙に見せる）
- 切り替え前に自動保存を `flush` し、本文とスペルチェックの下敷きを差し替える
- 選択中タブを `localStorage`（`writing:<id>:activePage`）に覚え、次回開いたときに復元する
- テスト: タブ列の HTML、空名のときの「ページ N」表示、最後の 1 枚の削除ボタン無効化、
  選択中タブが紙と同じ地色で影が親に 1 つだけ付くこと（CSS の文字列アサーション）

### Phase 4: API のページ対応

- `/save`・`/spellcheck`・`/chat`・`/title` に `pageId` を通し、ページの本文を読み書きする
- `/pages`・`/pages/:pageId/rename`・`/pages/:pageId/delete` を追加、`sanitizePageName()` を新設
- ページ 1 の本文は `compositions.english_text` にもミラーして一覧のプレビューを保つ
- テスト: `pageId` 不正時の 404 / 400、リネームの整形、最後の 1 枚の削除が 409

### Phase 5: 後始末（任意）

- 一覧のプレビューを先頭ページから引くようにして `compositions.english_text` の書き込みを外す
- タブのドラッグ並べ替え
- 全ページを続けて読む / 印刷する導線（添削削除で読書ページが無くなるため、必要なら別途）

## 影響範囲

- `backend/src/db.ts` — `composition_pages` 追加・移行、添削系の読み書き削除
- `backend/src/admin.ts` — 執筆画面のルート、ページ API、添削・読書・添削ログ画面の削除、一覧の列
- `backend/src/compositionView.ts` — タブ UI（HTML・CSS・スクリプト）、`renderCompositionReadPageHtml()` 削除
- `backend/src/compositionChat.ts` / `compositionTitle.ts` — 受け取る本文がページ単位になる（引数は既に本文文字列なので変更は呼び出し側）
- `backend/src/index.ts` — `/api/writing-feedback` 削除
- `backend/src/config.ts` — `writingFeedbackModel` 削除
- 削除: `backend/src/writingFeedback.ts` / `writingFeedbackRunner.ts` / `backend/test/writingFeedback.test.ts`
- `ios/.../Models/Composition.swift` — 添削レスポンス型の定義が未使用のまま残る。今回は触らない（別タスク）

## テスト方針

- `npm test`（`backend/`）で単体テストを回す。HTML はこれまでどおり文字列アサーションで確かめる
- 移行の検証は「title 列追加」と同じく、ページ 0 件の作文を作ってから移行関数を呼ぶ形で行う
- 手動確認:
  1. 既存の作文を開き、1 枚のタブ（「ページ 1」）に本文がそのまま残っている
  2. ＋ で 3 枚まで増やし、それぞれ別の本文を書いて再読み込みしても混ざらない
  3. タブ名をその場で編集して確定・取り消しが効く。空名は「ページ N」に戻る
  4. ページを切り替えた直後にチャットへ質問し、選択中ページの本文について答える
  5. スペルチェックの赤い波線が切り替え後のページに正しく付く
  6. 最後の 1 枚は削除できない。本文入りのページ削除は確認ダイアログが出る
  7. 選択中のタブと紙の間に境目・段差・影の切れ目が見えない（タブと紙が 1 枚に見える）

## 未確定 / 相談したいこと

- 添削削除にともない `/admin/writing-feedback`（添削ログ画面）とサイドバー項目も消す前提で書いた。
  ログの閲覧だけ残したい場合は Phase 1 から外す。
- 一覧の「状態」列は添削削除で空くので、代わりに「ページ数」を出すかどうか。
