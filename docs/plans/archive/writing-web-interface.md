# Writing 機能の Web インターフェース化

## 目的・背景

英作文（Composition）は現在 iOS アプリ内でのみ書ける。ソフトウェアキーボードでの長文入力は負荷が高く、
「書く」行為の主戦場は PC のキーボードにするのが自然。あわせて、書いた作文と AI 添削を
読みやすいタイポグラフィで表示し、スマホからも読めるようにする。

TODO の元項目:

- Writing 機能を変更する
  - PC で Web インターフェースを使って書くのをメインにする
  - 読みやすいフォントやレイアウトで表示
  - スマホで表示

## 現状（as-is）

- 作文データ `Composition` / `WritingRound` / `WritingFeedback` は **iOS の SwiftData ローカルのみ**
  （`ios/ESLLearningAssistant/Sources/Models/Composition.swift`）。サーバは本文を保存しない方針だった。
- 画面は `Views/CompositionsView.swift`（一覧）と `Views/CompositionDetailView.swift`（編集＋添削履歴）。
  タブ `AppTab.writing` として `ContentView.swift:31` に登録。
- 添削は `POST /api/writing-feedback`（`backend/src/index.ts:797`）→ `backend/src/writingFeedback.ts`。
  サーバ側は `writing_feedback_requests` テーブルに **通信ログとしてのみ**残す（`backend/src/db.ts:114`）。
- 管理画面 `/admin` は Cloudflare Access（エッジ）で保護、サーバサイド HTML 文字列生成（`backend/src/admin.ts`、ビルド不要）。
  `/admin/writing-feedback` は「作文添削ログ」の閲覧画面で、作文の作成・編集はできない。

## 方針（to-be）

**サーバを作文の正とし、書く・添削する・読む をすべて `/admin` 内の Web 画面で行う。iOS からは Writing を外す。**

決定事項（本プラン作成時にユーザーと合意）:

1. **iOS からは一旦外す** — Writing タブと関連画面を削除。将来サーバ参照の閲覧画面を戻す余地は残す。
2. **Web UI は `/admin` 内に1画面として追加** — 既存の admin テーマ・ヘルパー・Cloudflare Access 認証を流用する。
   学習者向けの独立アプリ（`/writing` や SPA）は作らない。

補足の設計判断:

- 添削ラウンドの積み上げ（`history` を渡して文脈込みで再添削）は現行の iOS 実装をそのまま Web に移す。
- 単一ユーザー運用のため、下書き保存に楽観ロック（vibeboard のような mtime チェック）は入れない。最終書き込み優先。
- `writing_feedback_requests`（通信・課金ログ）は温存し、作文本体テーブルと役割を分ける
  （`words` と `word_info_requests` の関係と同じ）。

## 影響範囲

| 対象 | 変更 |
| --- | --- |
| `backend/src/db.ts` | `compositions` / `composition_rounds` テーブルと CRUD 関数を追加 |
| `backend/src/writingFeedback.ts`（または新規 runner） | 添削生成＋ログ記録を index.ts から切り出し、admin からも呼べるようにする |
| `backend/src/index.ts` | `/api/writing-feedback` を共通関数呼び出しに置き換え（外部 I/F は不変）。`/admin` 向けに `express.urlencoded` を限定適用 |
| `backend/src/admin.ts` | `NavSection`/`NAV_ITEMS` に `writing` を追加。一覧・編集・添削・読書用の各ルートとスタイルを追加 |
| `backend/test/` | 作文 CRUD とレンダリングのテストを追加 |
| iOS | Writing タブ・2画面・`RemoteWritingFeedbackService`・UI テストを削除（モデルは残置） |

## Phase 1: サーバに作文を保存する

**Step 1-1. スキーマ追加（`backend/src/db.ts`）**

```sql
CREATE TABLE IF NOT EXISTS compositions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  english_text TEXT NOT NULL DEFAULT '',
  japanese_text TEXT NOT NULL DEFAULT '',
  explanation_language TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS composition_rounds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  composition_id INTEGER NOT NULL REFERENCES compositions(id) ON DELETE CASCADE,
  round_index INTEGER NOT NULL,          -- 1 始まり。古い順の並びに使う
  english_text TEXT NOT NULL,            -- そのラウンドで送った英文
  japanese_text TEXT NOT NULL,           -- そのラウンドで送った意図
  corrected_text TEXT NOT NULL,
  explanation TEXT NOT NULL,
  model TEXT NOT NULL,
  created_at TEXT NOT NULL,
  UNIQUE(composition_id, round_index)
);
```

- 既存テーブルと同じく `CREATE TABLE IF NOT EXISTS` で追記（既存 DB はそのまま開ける）。
- 外部キーの CASCADE を効かせるため `PRAGMA foreign_keys = ON` の設定有無を確認し、無ければ削除時に
  明示的に `composition_rounds` を先に消す。

**Step 1-2. CRUD 関数**

`listCompositions(limit, offset)` / `getComposition(id)` / `insertComposition(explanationLanguage)` /
`updateCompositionDraft(id, englishText, japaneseText)` / `deleteComposition(id)` /
`listCompositionRounds(compositionId)` / `insertCompositionRound(...)`。
一覧行には「ラウンド数」「下書きが最終ラウンドと同一か」の判定に必要な情報を含める。

**Step 1-3. 添削生成の共通化**

`index.ts:797` の `/api/writing-feedback` から、バリデーション（`WRITING_TEXT_MAX_LENGTH = 5000`）・
`generateWritingFeedback` 呼び出し・`insertWritingFeedbackLog`（コスト算出込み）の一連を関数に切り出す。
admin 側の Review もこの関数を通し、**課金ログが二重計上されないよう記録は1か所**に保つ。

**テスト**: `backend/test/compositions.test.ts`（`DATA_DIR` 隔離）で CRUD、ラウンドの順序保持、
削除時の子行削除を検証。

## Phase 2: `/admin/writing` — PC で書く画面

**ルート**（すべて `adminRouter`。既存 `/admin/writing-feedback`（ログ）とはパスが別で衝突しない）

| メソッド | パス | 役割 |
| --- | --- | --- |
| GET | `/admin/writing` | 作文一覧（更新日時降順、状態バッジ、新規ボタン） |
| POST | `/admin/writing/new` | 空の作文を作成し `/admin/writing/:id` へ 303 |
| GET | `/admin/writing/:id` | 編集画面（履歴＋下書きエディタ） |
| POST | `/admin/writing/:id/save` | 下書き保存（fetch からの JSON） |
| POST | `/admin/writing/:id/review` | 保存 → 添削 → ラウンド追加 → 編集画面へリダイレクト |
| POST | `/admin/writing/:id/delete` | 削除 |
| GET | `/admin/writing/:id/read` | 読書用ページ（Phase 3） |

- 状態バッジは iOS の `CompositionRow` と同じ 3 状態（未添削 / 編集中 / 添削済み ×N）。
- 編集画面は上から「これまでのラウンド（古い順）」→「下書き（英文 / 伝えたかった意図）」→「Review ボタン」。
  現行 `CompositionDetailView` の構成を踏襲する。
- Review は `canReview` 相当のガード（英日とも非空、かつ下書きが最終ラウンドと相違）をサーバ側でも検証。
- `history` は全ラウンドを渡し、文脈込みの再添削にする（現行と同じ）。
- フォーム POST を使う箇所があるため `app.use("/admin", express.urlencoded({ extended: false }))` を追加する
  （現状 `express.json` のみで、フォーム本文はパースされない）。fetch 保存は JSON なので既存 middleware で足りる。

**エディタ UX（PC 前提）**

- 英文 / 意図の 2 つの `textarea`。オートグロー（`scrollHeight` に追従）で長文でもスクロール分断しない。
- 自動保存: 入力停止 1.5 秒デバウンス＋ `blur` で `POST /save`。ヘッダに「保存済み / 保存中」表示。
- ショートカット: `⌘S`（保存）、`⌘Enter`（Review）。
- Review 実行中はボタンを無効化しスピナー表示。失敗時はページ内にエラーバナー。
- CSRF 対策は既存 admin の POST（delete / regenerate）と同水準（Cloudflare Access 前提）に揃え、新規の仕組みは足さない。

## Phase 3: 読みやすい表示とスマホ対応

**Step 3-1. リーディング用タイポグラフィ**

`backend/src/printView.ts` の思想（白地・serif・広い行間の独立ページ）を踏襲した本文スタイルを用意する。

- 本文フォント: `"Iowan Old Style", Georgia, "Hiragino Mincho ProN", serif`
- サイズ: `clamp(17px, 0.6vw + 15px, 20px)` / 行間 `1.9` / 段落間 `1.1em`
- 1行の長さ: `max-width: 68ch`（読みやすさの上限）、中央寄せ
- 解説は Markdown レンダリング（既存 `renderMarkdown` / `marked` を流用、エスケープ済み）

**Step 3-2. 対比レイアウト**

「You wrote / Corrected」は PC で 2 カラム（CSS Grid）に並べて差分を見比べられるようにし、
`@media (max-width: 720px)` で縦積みに落とす。解説は常に全幅。

**Step 3-3. 読書用ページ `/admin/writing/:id/read`**

添削済みの作文を通しで読むためのページ。admin のダークテーマ・サイドバーを外し、
`printView` 同様の単独ページとして描画する（印刷にもそのまま使える）。編集画面から導線を張る。

**Step 3-4. スマホ表示**

- `renderPage` には既に `viewport` meta があるためそのまま利用。
- `PAGE_STYLE` に `@media (max-width: 720px)` を追加し、サイドバーを横並び（上部の横スクロールナビ）に切り替える。
  全 admin ページに効く共通改善だが、変更は最小限（`.layout` を縦積み、`.sidebar` の `position: sticky; height: 100vh` を解除）に留める。
- 入力欄の `font-size` は 16px 以上（iOS Safari の自動ズーム回避）。
- タップ領域は 44px 以上。テーブルは既存 `.card { overflow-x: auto }` により横スクロールで破綻しない。
- スマホでの主用途は「一覧を見る・読む」。編集も可能だが最適化対象は PC とする。

**テスト**: 読書用ページの HTML 生成を純粋関数に切り出し、`backend/test/` でエスケープ・段落化・
ラウンド順を検証（`printView.test.ts` と同じ形）。実機 iPhone Safari での目視確認を手動で行う。

## Phase 4: iOS から Writing を外す

- `ContentView.swift` からタブ削除、`Support/AppRouter.swift` の `AppTab.writing` と参照箇所を削除。
- 削除するファイル: `Views/CompositionsView.swift`、`Views/CompositionDetailView.swift`、
  `Services/RemoteWritingFeedbackService.swift`、`ESLLearningAssistantUITests/CompositionUITests.swift`。
- **`Models/Composition.swift` と `ModelContainer` への登録は残置する。**
  SwiftData はスキーマからエンティティを外すと既存ストアが開けなくなるリスクがあるため
  （`ESLLearningAssistantApp.swift:14` ほか、プレビューの `modelContainer(for:)` 列挙もそのまま）。
  `DebugDataCleaner.deleteAllCompositions` も残す。
- ファイル削除後に `xcodegen generate`（pbxproj は生成物）。
- 端末ローカルに残る既存の作文はアプリからは見えなくなる。**移行は行わない**方針
  （必要なら Phase 4 の実施前に、当該作文を Web 画面へ手でコピーする）。
- サーバの `POST /api/writing-feedback` は iOS から呼ばれなくなるが、**API は残す**（admin が同じ生成ロジックを共有するため）。

## テスト方針

- backend: `npm test`（`backend/test/**/*.test.ts`）に Phase 1 / Phase 3 のテストを追加。
- 手動（PC）: 新規作成 → 保存 → Review → 下書き修正 → Re-review でラウンドが積まれること、
  `/admin/usage` に作文添削のコストが 1 回分だけ計上されること。
- 手動（スマホ）: 一覧・編集・読書ページが iPhone Safari で横スクロールせずに読めること。
- iOS: `xcodebuild test` で削除後にビルドと既存テストが通ること、既存ストアが問題なく開くこと（実機で起動確認）。

## 将来の拡張候補（今回はやらない）

- iOS 側にサーバ参照の作文閲覧画面を戻す（`GET /api/compositions` を追加して読み取り専用で同期）。
- 作文本文の単語タップ → 単語帳登録（iOS の `TappableEnglishText` 相当を Web で実現）。
- 修正前後の差分ハイライト（word-level diff）。
- タイトル・タグ付けによる作文の整理。
