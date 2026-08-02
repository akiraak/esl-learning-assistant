# 管理画面の作文でスペルミスを強調表示

## 目的・背景

`/admin/writing/:id`（執筆画面）は「左に罫線紙、右に AI チャット」の 2 ペインで、紙の上の
`textarea` に英文を書いていく（`backend/src/compositionView.ts:292`）。
この `textarea` には `spellcheck="true"` が付いておりブラウザ標準の綴り検査は効くが、

- OS / ブラウザの言語設定に依存し、環境によって効いたり効かなかったりする
- 標準の赤い波線は控えめで、紙の風合い（serif・19px・行送り 34px）の中では気づきにくい
- 学習者が単語帳に登録済みの語（`words` テーブル）まで無関係に赤くなる可能性がある

書きながら綴りの誤りに気づけるよう、**サーバ側の辞書で判定した結果を紙の上に自前で強調表示する**。

TODO の元項目:

- 管理画面の作文でスペルミスを強調表示

## 決定事項（プラン作成時にユーザーと合意）

1. **判定は辞書ベースで自前実装**（AI には投げない）。即時・無料で、入力中もリアルタイムに出せる。
   文脈依存の誤用（`its` / `it's`、`there` / `their`）は拾えないが、そこは既存の AI 添削・
   AI チャットの担当とし、本機能は「綴りが辞書に無い語」に限定する。
2. **対象画面は執筆画面 `/admin/writing/:id` のみ**。読書用ページ `/read` と一覧 `/admin/writing`
   には入れない（後から足せる形にはしておく）。

## 方針（to-be）

### 辞書は typo-js（hunspell 互換, en_US 同梱）

| 検討 | 判断 |
| --- | --- |
| `nspell` + `dictionary-en` | `dictionary-en@4` が ESM のみ。backend は `"type": "commonjs"` なので採用しない |
| `word-list`（SCOWL の語彙リスト） | ESM のみ。かつ修正候補を出せない |
| **`typo-js@1.3.2`** | **CommonJS（`main: typo.js`）。`dictionaries/en_US/en_US.{aff,dic}` を同梱。`check()` と `suggest()` の両方を持つ** |

実測（`node -e` で確認済み）:

- 辞書ロード 52ms（プロセス起動時に 1 回だけ。以降はメモリ常駐）
- `check()` は 20,000 回で約 1ms → 本文全体を毎回走査しても体感ゼロ
- `recieve` → `["relieve", "receive", "recipe"]`、`yesteday` → `["yesterday", "Yesterday"]`
- パッケージは 557KB（tgz）

### 判定はサーバ、描画はクライアント

```
POST /admin/writing/:id/spellcheck
  { "text": "I recieve a letter yesteday." }
→ { "misspellings": [
     { "start": 2,  "end": 9,  "word": "recieve",  "suggestions": ["receive", "relieve"] },
     { "start": 19, "end": 27, "word": "yesteday", "suggestions": ["yesterday"] }
   ] }
```

- 辞書をブラウザへ配らずに済む（557KB を毎回読ませない）
- 学習者が登録済みの単語（`listStoredWordTexts`）を例外辞書として合流できる
- 判定ロジックが純粋関数になり `node --test` で検証できる（`printView` / `compositionView` と同じ方針）

`start` / `end` は `textarea.value` に対する文字オフセット。クライアントは同じ文字列を送っているので
そのままハイライト位置に使える。

### 紙の上への重ね方（backdrop overlay）

`textarea` 自体には装飾を入れられないので、**同じ書体・同じ行送りの複製テキストを背後に敷いて、
該当語にだけ下線を描く**（highlight-within-textarea の定石）。

```
.sheet (position: relative)
 ├─ .paper-backdrop  ← 複製テキスト（color: transparent）／ <mark> に赤い波線
 └─ .paper (textarea) ← 透明背景・z-index 上／実際に見えている字はこちら
```

ズレを起こさないための制約（既存 CSS の作りとかみ合う）:

- `.paper` は既に `padding: 0` / `border: none` で、余白は `.sheet` 側が持っている
  → backdrop は `.sheet` の padding と同じ inset に置けば座標が一致する
- `font-family` / `font-size: 19px` / `line-height: 34px` / `white-space: pre-wrap` /
  `word-wrap: break-word` を `.paper` と共有する（CSS を 1 つのクラスにまとめて両方へ当てる）
- `textarea` はオートグロー（`autogrow()`）で内容の高さまで伸び、スクロールは `.paper-pane` 側が担うので
  **スクロール位置の同期は不要**
- 末尾改行が潰れないよう、backdrop に入れる文字列は末尾の `\n` の後ろに空白を 1 つ足す

強調のスタイルは「紙にペンで引いた印」に寄せる:

```css
.paper-backdrop mark {
  background: none; color: transparent;
  text-decoration: underline wavy;
  text-decoration-color: rgba(163,57,47,0.75); /* toolbar の削除ボタンと同系の赤 */
  text-decoration-skip-ink: none;
}
```

自前の下線と標準の波線が二重に出るのを避けるため、`.paper` の `spellcheck` は `"false"` に切り替える。

### 判定を走らせるタイミング

| 契機 | 動き |
| --- | --- |
| 初回描画 | サーバ側で判定し、結果を `<script>` に埋め込む（初期表示から赤線が出ている状態） |
| 入力停止 600ms | `POST /spellcheck` して結果を差し替える（自動保存の 1.5 秒デバウンスとは独立） |
| 通信失敗 | 直前の結果を残したまま黙って諦める（書く手を止めない。保存失敗のような表示は出さない） |

**入力中の語は赤くしない**: カーソル位置が語の範囲内（`start <= caret <= end`）にある語は描画から外す。
`recieve` と打つ途中の `reci` が毎回赤くなるのを防ぐ。

### トークナイズの規則（実測にもとづく）

`typo-js` に投げる前の切り出しで結果がかなり変わるので、規則を明示する。

| 入力 | 扱い | 理由 |
| --- | --- | --- |
| `doesn't` / `I've` | アポストロフィを語に含めて 1 語 | 分割すると `doesn` が誤検出（辞書は `doesn't` を持つ） |
| `well-known` / `e-mail` | ハイフンで分割し各片を判定 | 辞書はハイフン付き複合語を持たない（`well-known` は false） |
| `2026` / `30th` | 数字を含む語はスキップ | `2026` は辞書に無く常に誤検出になる |
| `U.S.` | ピリオドを含む語はスキップ | 略語は辞書に無い |
| `https://…` / `foo@bar.com` | URL・メールはスキップ | 語として判定する意味がない |
| 日本語・記号 | ASCII 英字を含まない語はスキップ | 英文だけを対象にする |

`typo-js` は大文字化には対応する（`RECEIVE` は true、`RECIEVE` は false）ので大小の正規化は不要。

### 既知の限界（仕様として受け入れる）

- **英国綴りは誤検出**: `colour` / `favourite` は en_US 辞書に無く赤くなる（同梱辞書は en_US と it のみ）
- **綴りは正しいが用法が誤りの語は拾えない**: `cant` / `wanna` は辞書にあるので通る
- **固有名詞は誤検出**: `Akira` / `Kozakai` は false（`Seattle` / `NASA` / `Tokyo` は true）
  → Phase 3 の無視リストで潰す

## 実装時の変更点（プランからの差分）

**修正候補は一括では返さない**。実装中に測ったところ `suggest()` は 1 語あたり約 1.2 秒かかった
（`check()` は 20,000 回で 1ms）。本文全体の誤りにまとめて候補を付けると、入力停止のたびに
数秒待つことになる。そのため:

- `findMisspellings()` の戻り値は `{ start, end, word }` のみ（`suggestions` を持たない）
- 候補は `suggestCorrections(word)` として分け、赤い語にカーソルを置いた時にその 1 語だけ求める
  （`POST /admin/writing/spell-suggest`）。同じ語は プロセス内にキャッシュする

**「入力中の語を赤くしない」の条件**。カーソル位置だけで判定すると、赤い語をクリックして
ポップオーバーを開こうとした瞬間に赤線が消えてしまう。そのため「打鍵の直後」に限って
カーソル上の語を伏せ、クリック・カーソル移動キーでは伏せない。

## 影響範囲

| 対象 | 変更 |
| --- | --- |
| `backend/package.json` | `typo-js@^1.3.2` を dependencies に追加 |
| `backend/src/spellcheck.ts`（新規） | トークナイズと判定。db.ts を読み込まない純粋モジュール（例外語は引数で受ける） |
| `backend/src/compositionView.ts` | backdrop の DOM・CSS・ハイライト描画スクリプトを追加。初期判定結果を `CompositionEditorPage` に足す |
| `backend/src/admin.ts` | `POST /admin/writing/:id/spellcheck` を追加。`GET /admin/writing/:id` で初期判定を渡す |
| `backend/test/spellcheck.test.ts`（新規） | トークナイズ規則・オフセット・例外辞書の検証 |
| `backend/test/compositionView.test.ts` | backdrop が出ること・エスケープされることを追加検証 |

iOS 側の変更は無い。

## Phase 1: サーバ側のスペル判定

**Step 1-1. `typo-js` を追加**

`npm i typo-js` （`backend/`）。CommonJS なので `import Typo from "typo-js"` ではなく
`const Typo = require("typo-js")` 相当（`esModuleInterop` の設定を確認して合わせる）。

**Step 1-2. `backend/src/spellcheck.ts`**

```ts
export interface Misspelling {
  start: number;  // text 内の文字オフセット（終端は排他）
  end: number;
  word: string;
  suggestions: string[];  // 最大 3 件
}

/// text を語に切り出し、辞書にも例外語にも無いものを返す。
/// ignoredWords は小文字化して照合する（単語帳の登録語・無視リスト）。
export function findMisspellings(text: string, ignoredWords: Iterable<string>): Misspelling[]
```

- 辞書はモジュール内で遅延生成し 1 度だけロードする（52ms を毎リクエスト払わない）
- 語の切り出しは上表の規則をそのまま実装する。正規表現は 1 本にせず、
  「候補の切り出し → スキップ判定 → ハイフン分割」の 3 段に分けて読めるようにする
- `suggestions` は `suggest()` の先頭 3 件

**Step 1-3. `POST /admin/writing/:id/spellcheck`（`admin.ts`）**

- 作文が無ければ 404、`text` が文字列でなければ 400（`/save` と同じ形）
- 例外語は `listStoredWordTexts(config.targetLanguage 相当)` から取る（Phase 3 で無視リストを合流）
- `WRITING_TEXT_MAX_LENGTH` を超える本文は判定せず空配列を返す（`/save` 側のバリデーションと揃える）
- AI を呼ばないので利用料金ログ（`/admin/usage`）には**記録しない**

**テスト**: `backend/test/spellcheck.test.ts`

- `I recieve a letter yesteday.` で 2 件・オフセットが `text.slice(start, end)` と一致する
- `doesn't` / `I've` を誤検出しない、`well-known` は片方だけ誤りなら片方だけ返す
- `2026` / `U.S.` / `https://example.com` / 日本語をスキップする
- `ignoredWords` に渡した語（大小・前後空白違いを含む）は返らない
- 空文字・空白のみで空配列

## Phase 2: 執筆画面のハイライト

**Step 2-1. backdrop の DOM と CSS（`compositionView.ts`）**

- `.sheet` を `position: relative` にし、`<div class="paper-backdrop" aria-hidden="true"></div>` を
  `textarea` の**前**に置く（背後に敷く）
- `.paper` と `.paper-backdrop` で共有する字組みプロパティを 1 か所にまとめ、
  `PAPER_LINE_HEIGHT_PX` と同じく「両方を同じ値から組み立てる」形にする
  （ここがズレると赤線が字の下に来ない。既存の罫線と同じ地雷）
- `.paper` に `position: relative; z-index: 1`、`spellcheck="false"` を設定
- `@media print` では backdrop を消す（印刷物に赤線は不要）

**Step 2-2. ハイライト描画（クライアントスクリプト）**

```js
function renderMarks(text, spans, caret) {
  // spans を start 昇順で走査し、間の素テキストと <mark> を組み立てる。
  // 素テキストは createTextNode 相当のエスケープを通す（本文が HTML として解釈されないように）。
  // caret が span の内側にあるものは飛ばす（入力中の語は赤くしない）。
}
```

- サーバから受け取ったオフセットは、返答が届いた時点の本文と食い違いうる
  （返答待ちの間に打鍵が進む）。**リクエスト時の本文を保持しておき、返答時に現在の本文と
  一致するときだけ反映する**（一致しなければ捨てて次のデバウンスに任せる）
- `input` イベントで既存の `autogrow()` に続けて 600ms デバウンスの判定を仕込む
- `selectionchange` / `click` / `keyup` でカーソル位置が変わったら、既存の spans のまま再描画だけ行う
  （通信なしで「打ち終えた語が赤くなる」挙動になる）

**Step 2-3. 初期表示**

`renderCompositionEditorPageHtml` の `CompositionEditorPage` に `misspellings: Misspelling[]` を足し、
`jsonForScript` で埋め込む。ページを開いた瞬間から赤線が出ている状態にする。

**テスト**: `backend/test/compositionView.test.ts` に追加

- 初期 `misspellings` が `<script>` に JSON として埋まる（`</script>` を含む本文でも壊れない）
- backdrop 要素と `.paper-backdrop mark` のスタイルが出力に含まれる
- `spellcheck="false"` になっている

**手動確認**: ローカルサーバで

- `I recieve a letter yesteday.` と打ち、赤い波線が該当語の下に**罫線と重ならず**出る
- 打鍵中の語は赤くならず、スペースを打った瞬間に赤くなる
- 長文（罫線 3 画面分）で下線が下の行ほどズレていかない
- ⌘S・自動保存・AI チャットが従来どおり動く（保存状態表示が壊れない）
- 幅 390px（`@media (max-width: 900px)` の縦積み）でも下線位置が合う

## Phase 3: 誤検出を潰す無視リスト

Phase 2 までで実用になるが、固有名詞（`Akira` / `Kozakai` など）が赤いままだと
「赤線＝直すべき箇所」という信号が濁るので、辞書に足せるようにする。

- `spell_ignored_words` テーブル（`word TEXT PRIMARY KEY`, `created_at`）を `db.ts` に追加
- 赤い語をクリック → 小さなポップオーバーで修正候補（`suggestions`）と「辞書に追加」を出す
  - 候補を選ぶと本文を置換して保存
  - 「辞書に追加」で `POST /admin/writing/spell-ignore` → 以後どの作文でも赤くならない
- 判定時の例外語は `listStoredWordTexts()` と無視リストの和集合

**テスト**: 無視リストの CRUD（`DATA_DIR` 隔離、`compositions.test.ts` と同じ形）と、
`findMisspellings` に和集合を渡したときに除外されること。

## テスト方針

- backend: `npm test`（`node --test`）に Phase 1 / Phase 2 / Phase 3 のテストを追加。
  既存 118 件が壊れないこと
- ハイライトの位置合わせは自動テストでは担保できないため、上記の手動確認を必須とする
  （罫線と本文の行送りを揃えたときと同じく、**目視でしか分からない種類のズレ**）
- AI を呼ばないので `/admin/usage` の計上に影響が無いことを確認する

## 将来の拡張候補（今回はやらない）

- 読書用ページ `/read` の「You wrote」側を強調表示（今回は執筆画面のみと決定）
- 一覧 `/admin/writing` に「スペルミス N 件」バッジ
- 英国綴りの許容（en_GB 辞書の追加、または `colour` 系を無視リストに一括投入）
- 綴りは正しいが文脈的に誤りの語（`its` / `it's`）を AI で精査するモード
