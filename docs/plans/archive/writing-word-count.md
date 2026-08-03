# 執筆画面にワード数を表示する

## 目的・背景

執筆画面（`/admin/writing/:id`）には、いま書いている英文が何語あるかを知る手がかりがない。
語数は英作文の課題でよく指定される単位なので、書きながら目に入る位置に欲しい。

ツールバー（`backend/src/compositionView.ts` の `.toolbar`）には既に保存状態
（`#save-status`）を出す場所があり、ここに並べれば新しい面積を使わずに済む。

## 決定事項（プラン作成時にユーザーと合意）

1. 出す場所は**ツールバーの右上**。`← 作文一覧 … 123 words ・ 保存済み [削除]` と並べる。
2. 数える範囲は**普段は見ているページ（タブ）1枚**、英文を**選択している間はその選択範囲**。
   選択翻訳（docs/plans/archive/writing-selection-translate.md）と同じ範囲を見ることになる。

## 方針（to-be）

### 数え方

文字か数字のかたまりを1語とし、語中のアポストロフィ・ハイフンは繋いだままにする
（`don't` / `well-known` は 1 語）。句読点や記号だけのかたまりは数えない。

規則は `composition.ts` に置き、サーバと画面で**同じ正規表現を共有**する。

```ts
export const WORD_PATTERN_SOURCE = "[\\p{L}\\p{N}]+(?:['’\\-][\\p{L}\\p{N}]+)*";
export function countWords(text: string): number;
```

画面側は `new RegExp(<source>, 'gu')` を作って同じ規則で数えるので、
規則の検証は `composition.test.ts` に集約できる（画面側に別のルールを持たない）。

### 表示

- 初期値はサーバが数えて HTML に埋める（開いた直後にちらつかせない）。
- 文言は `wordCountLabel(count, selected)`。1 語のときだけ単数形（`1 word`）、
  選択中は「選択」を前に付けて、どちらの数か分かるようにする。
- 更新は `renderMarks()` の末尾で行う。本文が変わっても選択が変わっても必ずここを通るので、
  イベントの張り忘れが起きない。

### ついでに直す

ページ（タブ）を切り替えたとき、前のページで選んでいた範囲（`selRange`）が残ったままだった。
`showPage()` で `clearSelectionMark()` を通し、選択マークと和訳の紙片を持ち越さないようにする。

## 影響範囲

| ファイル | 変更 |
| --- | --- |
| `backend/src/composition.ts` | `WORD_PATTERN_SOURCE` / `countWords` を追加 |
| `backend/src/compositionView.ts` | `wordCountLabel`、ツールバーの語数、画面側の数え直し、`showPage` の選択解除 |
| `backend/test/composition.test.ts` | 数え方の検証 |
| `backend/test/compositionView.test.ts` | 文言と生成 HTML の検証 |

サーバの API・DB・コスト集計は変更なし。

## テスト方針

- `composition.test.ts`: 空白区切り・記号のみ・アポストロフィ・ハイフン・数字・日本語。
- `compositionView.test.ts`: `wordCountLabel` の単複と「選択」、初期値の埋め込み、
  選択中は選択範囲を数えること、`renderMarks` から数え直すこと、`showPage` の選択解除。
- 手動（Playwright）: 打鍵で追随 / 選択中は「選択 N words」/ 解除で戻る / 1語は単数形 /
  タブを切り替えるとそのページの語数になること。
