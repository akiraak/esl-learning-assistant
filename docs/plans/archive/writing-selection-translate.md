# 管理画面の作文で英文を選択したら翻訳を表示する

## 目的・背景

`/admin/writing/:id` の執筆画面は、紙に見立てた `<textarea id="body" class="paper">`
（`backend/src/compositionView.ts:574-582`）に英文を書く。書いている途中で
「この一文の意味はこれで合っているか」を確かめたくなるが、いまは右ペインの相談チャット
（`POST /admin/writing/:id/chat`, `backend/src/admin.ts:1089`）に自分で貼り付けて聞くしかない。

本文の一部を選択しただけで和訳が読めれば、書く手を止めずに確認できる。
翻訳そのものは既に `translateText(text, targetLanguageCode, maxTokens)`
（`backend/src/ocrTranslate.ts:112`、`config.translateModel` = `claude-haiku-4-5`）があり、
写真OCR・音声文字起こし・文書抽出で使い回している。これをそのまま執筆画面からも呼ぶ。

表示に使うポップオーバーは、綴り修正候補の `.spell-pop`
（CSS `compositionView.ts:432-448`、DOM `:582`、ロジック `:850-981`）と同じ作りにできる。
位置決めも、下敷き `#backdrop` が本文入力欄と同一のタイポグラフィ契約
（`compositionView.ts:400-428`、`PAPER_LINE_HEIGHT_PX` `:85`）を持つので、
綴り誤りの `<mark>` と同じ手法（`getBoundingClientRect()`）で選択範囲の真下に出せる。

なお本文は `textarea` の中にあるため、選択範囲の取得は `window.getSelection()` ではなく
`input.selectionStart / selectionEnd`（既に `:774`, `:935` で使用）で行う。

## 決定事項（プラン作成時にユーザーと合意）

1. **トリガーは自動**。選択が確定した時点（`mouseup` / `keyup` / `selectionchange` の落ち着き）で
   自動的に翻訳を取りに行き、ポップオーバーに和訳を出す。「翻訳」ボタンを挟まない。
2. **リクエストログとコスト計上を行う**。`composition_title_requests`（`backend/src/db.ts:159`）と
   同じ形の追記ログテーブルを足し、`UsageFeature` に `writing-translate` を追加して
   `/admin/usage` の集計に載せる。
3. **同一文の再翻訳はキャッシュヒットとして無課金**にする。ログ行に `cache_hit` を持たせ、
   ヒット行はコスト 0 で記録する（既存 `requests` テーブルの `cache_hit` 列と同じ考え方）。
4. **周辺文脈を一緒にモデルへ渡す**。選択が一文〜数語と短く、それだけでは代名詞・時制・
   固有名詞の指す先が定まらないため、選択の前後それぞれ 200 文字を添え、
   「訳して返すのは選択部分だけ」と指示する。モデルは `config.translateModel`
   （`claude-haiku-4-5`）のまま据え置く。

## 方針（to-be）

### 全体の流れ

```
textarea で英文を選択
  → 250ms 静まったら選択文字列を確定（前後の空白を落とす）
  → 本文から選択の前後 200 文字ずつを切り出して文脈にする
  → クライアント側メモ（Map）にあれば即表示・通信なし
  → POST /admin/writing/:id/translate {text, contextBefore, contextAfter}
       → サーバ: 直近の成功ログを text_hash + target_language で検索
            ヒット   → その和訳を返す（cache_hit=1, cost 0 でログ）
            ミス     → 文脈付きで Claude を呼ぶ → 和訳を返す（cache_hit=0, cost 計上でログ）
  → 選択範囲の真下にポップオーバーで和訳を表示
```

自動トリガーなので、暴発と無駄打ちを次で抑える。

- **デバウンス 250ms**。ドラッグ中・シフト矢印での伸縮中は投げない。
- **下限**: trim 後 1 文字未満なら閉じるだけ。単語1つの選択も翻訳対象に含める。
- **上限**: 選択が `WRITING_TRANSLATE_MAX_LENGTH = 1000` 文字を超えたら投げず、
  ポップオーバーに「選択が長すぎます（1000文字まで）」と出す。
  （本文全体の上限は `WRITING_TEXT_MAX_LENGTH = 5000`、`backend/src/composition.ts`）
- **中断**: 選択が変わったら前のリクエストを `AbortController` で捨てる。
  遅れて届いた応答は、リクエスト時の選択範囲と現在の選択範囲が一致するときだけ描画する。
- **クライアント側メモ**: 正規化後テキスト → 和訳の `Map`。同じ文を選び直しても通信しない。

### 翻訳先の言語

`compositions.explanation_language`（`backend/src/db.ts:116`）をそのまま翻訳先の言語コードに渡す。
空なら `"ja"` にフォールバックする。

### 周辺文脈の渡し方

`translateText()`（`ocrTranslate.ts:112`）は「渡した文章全体を訳す」インタフェースで、
文脈だけ与えて訳させない、という指定ができない。そこで選択翻訳では
`callStructured()`（`ocrTranslate.ts:55`、`translateText` も内部で使っている共通ヘルパー）を
直接呼び、専用のスキーマとプロンプトを `compositionTranslate.ts` に置く。
モデルは同じ `config.translateModel`（`claude-haiku-4-5`）。

- 文脈量は前後それぞれ `WRITING_TRANSLATE_CONTEXT_CHARS = 200` 文字。
  同ページの本文からのみ取り、他ページ（タブ）はまたがない。
- 切り出しは文字数で機械的に行い、頭が語の途中で切れても気にしない
  （文脈として渡すだけで、訳出対象ではないため）。
- 選択が本文全体に近く文脈が空になる場合は、文脈なしのプロンプトに切り替える。

```
スキーマ  { translatedText: string }   // 選択部分の訳のみ
プロンプト（要旨）
  次の英文のうち、<selection> で囲んだ部分だけを言語コード "ja" に翻訳してください。
  前後の文はあくまで文脈で、訳文に含めないこと。代名詞・時制・固有名詞の指す先は文脈から判断すること。
  訳文だけを translatedText に入れること。
  ---
  {contextBefore}<selection>{text}</selection>{contextAfter}
```

**キャッシュキーへの影響**: 文脈が変われば訳も変わり得るので、`selectionHash()` は
(翻訳先言語, contextBefore, 選択テキスト, contextAfter) の全部から作る。
本文を書き足すと同じ文でもキャッシュを外すことになるが、
「同じ場所を選び直す」という一番多い操作はクライアント側メモが受け止めるので実害は小さい。

### サーバ側

**新規モジュール `backend/src/compositionTranslate.ts`**（DB 非依存。`node --test` から直接読める）

```ts
export const WRITING_TRANSLATE_MAX_LENGTH = 1000;
export const WRITING_TRANSLATE_CONTEXT_CHARS = 200;

/// 選択文字列を通信・キャッシュキーに使える形へ整える（純関数）。
/// 前後の空白除去、改行そのまま（段落選択を壊さない）、連続空白は畳まない。
export function normalizeSelection(raw: string): string;

/// 本文と選択範囲から前後の文脈を切り出す（純関数）。それぞれ最大 200 文字。
export function selectionContext(body: string, start: number, end: number):
  { before: string; after: string };

/// キャッシュキー。言語コードと文脈込みで sha256 を作る。
export function selectionHash(
  text: string, targetLanguage: string, contextBefore: string, contextAfter: string
): string;

/// 翻訳本体。callStructured() を文脈付きプロンプトで呼び、
/// モデル名・トークン数をそのまま返す。
export async function translateSelection(input: {
  text: string; targetLanguage: string; contextBefore: string; contextAfter: string;
}): Promise<{ text: string; model: string; inputTokens: number; outputTokens: number }>;
```

**新規テーブル `composition_translate_requests`**（`backend/src/db.ts` に `CREATE TABLE IF NOT EXISTS`）

| 列 | 用途 |
| --- | --- |
| `id` | PK |
| `created_at` | 記録時刻 |
| `composition_id` | どの作文からの選択か |
| `text_hash` | `selectionHash()` の値。キャッシュ検索キー |
| `target_language` | 翻訳先言語コード |
| `source_text` | 選択された英文（1000文字上限なのでそのまま持つ） |
| `context_before` / `context_after` | モデルに渡した前後の文脈（各200文字。後から訳を検証できるように残す） |
| `translated_text` | 和訳（失敗時 NULL） |
| `model` / `input_tokens` / `output_tokens` / `cost_usd` | 課金集計用 |
| `status` / `error_message` / `latency_ms` | 成否と所要時間 |
| `cache_hit` | 1 ならAPI未使用（コスト 0） |

索引: `CREATE INDEX ... ON composition_translate_requests(text_hash, target_language, status)`。

**新規ルート `POST /admin/writing/:id/translate`**（`backend/src/admin.ts`、
タイトル生成 `:1222-1281` と同じ骨格＝開始ログ → 呼び出し → 成功/失敗どちらもログ行を残す）

```
リクエスト  {
  "text": "He have been studying English.",
  "contextBefore": "My brother moved to Canada last year. ",
  "contextAfter": " He says it is still hard to speak."
}
成功        { "translatedText": "彼は英語を勉強してきた。", "cached": false }
長すぎ      400 { "error": "選択が長すぎます（1000文字まで）" }
空          400 { "error": "選択が空です" }
失敗        500 { "error": "<メッセージ>" }
```

`contextBefore` / `contextAfter` は画面が切り出して送るが、サーバ側でも
`WRITING_TRANSLATE_CONTEXT_CHARS` で末尾/先頭から切り詰めてから使う（クライアントを信用しない）。

キャッシュ検索は `SELECT translated_text FROM composition_translate_requests
WHERE text_hash = ? AND target_language = ? AND status = 'success' AND translated_text IS NOT NULL
ORDER BY id DESC LIMIT 1`。作文をまたいでヒットさせる（同じ英文なら訳も同じでよい）。

**コスト集計**（`backend/src/db.ts`, `backend/src/admin.ts`）

- `UsageFeature` に `"writing-translate"` を追加（`db.ts:1901-1912`）。
- `collectUsageEvents` に、`cache_hit = 0` の行を対象とした `push("writing-translate", ...)` を追加
  （`db.ts:2151` の `writing-title` と同じ形）。
- `USAGE_FEATURE_META` に `"writing-translate": { label: "作文翻訳", href: "/admin/writing" }`
  を追加（`admin.ts:1985` の隣）。
- キャッシュ由来の近似ではなく毎回の追記ログなので `USAGE_APPROX_FEATURES` には**入れない**。

### 画面側（`backend/src/compositionView.ts`）

**`CompositionEditorPage`**（`:113`）に `translateUrl: string` を追加し、
`admin.ts:1038` の編集ページ生成で `/admin/writing/${id}/translate` を渡す。
既存フィールドと同じく `jsonForScript()` でスクリプトへ埋める。

**DOM**: `#spell-pop` の隣に `<div class="trans-pop" id="trans-pop"></div>` を置く。

**CSS**: `.spell-pop` の紙片スタイルを土台にした `.trans-pop` を足す。
違いは、和訳は文章なので `max-width: 380px` / `line-height: 1.6` / 本文と同じ日本語フォント、
そして「読むだけ」なのでボタンを持たないこと。ローディングは既存の `.none` と同じ薄い文字で
「翻訳しています…」を出す。

**選択範囲の位置決め**: 下敷き `#backdrop` の `renderMarks()` を拡張し、綴りの `<mark>` に加えて
選択範囲を `<mark class="sel" data-sel="1">` として描く。ポップオーバーの位置は
`backdrop.querySelector('mark[data-sel="1"]').getBoundingClientRect()` の下端から取る
（複数行選択なら `getClientRects()` の最後の矩形を使い、選択の末尾行の下に出す）。

```
.paper-area
 ├ #backdrop   ← 綴り <mark> ＋ 選択 <mark class="sel"> を描く（透明・計測用）
 └ #body       ← 実際に打つ textarea（背景は透明）
#trans-pop     ← position: fixed で紙の上に浮かす（z-index は .spell-pop と同じ 5）
```

**綴りポップオーバーとの調停**（両方が同時に開かないようにする）

- 選択が空（キャレットだけ）→ これまでどおり `syncPopover()` が綴り候補を出す。
- 選択がある → 綴りポップオーバーを `closePopover()` で閉じ、翻訳ポップオーバーだけを開く。

**閉じる条件**: 既存の綴りポップオーバーと同じ集合（`compositionView.ts:973-981`）に合わせる。
入力 (`input`) / `Escape` / ポップ外の `mousedown` / `.paper-pane` のスクロール / `resize`、
加えて選択が空になったとき。閉じるときは進行中のリクエストも中断する。

## 影響範囲

| ファイル | 変更 |
| --- | --- |
| `backend/src/compositionTranslate.ts` | 新規（純粋ロジック＋`translateText` 呼び出し） |
| `backend/src/db.ts` | テーブル `composition_translate_requests` 追加、挿入/検索関数、`UsageFeature`、`collectUsageEvents` |
| `backend/src/admin.ts` | `POST /admin/writing/:id/translate` 追加、編集ページに `translateUrl`、`USAGE_FEATURE_META` |
| `backend/src/compositionView.ts` | `translateUrl` フィールド、`.trans-pop` の CSS・DOM・スクリプト、`renderMarks()` の選択描画 |
| `backend/test/compositionTranslate.test.ts` | 新規 |
| `backend/test/compositionView.test.ts` | 生成 HTML の検証を追加 |

既存の翻訳系エンドポイント（`/api/ocr-translate` ほか）と iOS クライアントには手を入れない。
DB は `CREATE TABLE IF NOT EXISTS` の追加だけで、既存テーブルの変更なし。

## Phase / Step 分割

### Phase 1: サーバ側

- Step 1-1: `compositionTranslate.ts` を作る（`normalizeSelection` / `selectionHash` / `translateSelection`）
- Step 1-2: `db.ts` に `composition_translate_requests` と挿入・キャッシュ検索関数を足す
- Step 1-3: `POST /admin/writing/:id/translate` を実装（キャッシュ判定・成功/失敗ログ）
- Step 1-4: `UsageFeature` / `collectUsageEvents` / `USAGE_FEATURE_META` に `writing-translate` を追加

### Phase 2: 画面側

- Step 2-1: `CompositionEditorPage.translateUrl` を追加し、`admin.ts` から渡す
- Step 2-2: `.trans-pop` の CSS と DOM、`renderMarks()` の選択 `<mark>` 描画
- Step 2-3: 選択検知（デバウンス・上下限・前後文脈の切り出し・中断・クライアントメモ）と表示、
  綴りポップオーバーとの調停
- Step 2-4: 閉じる条件とエラー表示の詰め

### Phase 3: 仕上げ

- Step 3-1: テスト追加（下記）
- Step 3-2: 実機で動作確認（`/admin/usage` に「作文翻訳」が出ること、再選択が無課金なこと）
- Step 3-3: `TODO.md` の項目を `DONE.md` へ、本プランを `docs/plans/archive/` へ移動

## テスト方針

`node --test`（`backend/test/`）。DB と Anthropic SDK に触らない純粋ロジックを分けてある前提で書く。

- `compositionTranslate.test.ts`
  - `normalizeSelection`: 前後空白の除去、改行の保持、空選択が空文字になること
  - `selectionContext`: 前後 200 文字ちょうど / 足りないとき / 本文の先頭・末尾を選んだとき（空文字）
  - `selectionHash`: 同じ (テキスト, 言語, 文脈) で同値、言語違い・文脈違いで別値
  - `WRITING_TRANSLATE_MAX_LENGTH` 超過の判定境界（1000 / 1001 文字）
- `compositionView.test.ts`（追記）
  - 生成 HTML に `#trans-pop` が含まれること
  - `translateUrl` がスクリプトへ正しくエスケープされて埋まること
- 手動確認
  - 1単語 / 一文 / 複数行の選択でポップオーバーが選択末尾行の下に出る
  - 選択をすばやく変えたとき、古い応答が新しい選択の上に描かれない
  - 1000文字超の選択で通信が発生せず注意文だけ出る
  - 同じ文を選び直すと通信が飛ばない（2回目以降）／別セッションでもサーバ側キャッシュが効く
  - キャレットだけのとき綴り候補が従来どおり出る（翻訳ポップと二重に開かない）
  - 代名詞を含む短い選択（例: "He says it is still hard to speak."）で、前の文の主語を踏まえた訳になる
  - 訳文に文脈部分の訳が混ざっていない（選択部分だけが返る）
