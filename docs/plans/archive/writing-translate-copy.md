# 選択翻訳の和訳をコピーできるようにする

## 目的・背景

執筆画面（`/admin/writing/:id`）で英文を選ぶと出る和訳の紙片 `.trans-pop`
（`backend/src/compositionView.ts`、docs/plans/archive/writing-selection-translate.md）は
いま「読むだけ」で、訳文を手元に取り出せない。ノートや別の資料へ写したいときに、
文字を選び直してコピーする操作が必要になっている。

チャット側には既に同じ用途のボタンがある。AI の返信の英文ブロックに後付けする
`.copy-btn`（CSS `compositionView.ts:516-523`、生成 `decorateCopyTargets`、
クリップボード操作 `copyText`）で、`navigator.clipboard` が使えない環境では
`execCommand('copy')` に落ちる作りになっている。同じ見た目・同じ関数を和訳の紙片でも使う。

## 決定事項

1. 和訳が出ているときだけボタンを出す。「翻訳しています…」「翻訳できませんでした」
   「選択が長すぎます」といった案内文（`.note`）には付けない。
2. コピーするのは**和訳のみ**（元の英文は含めない）。英文は選択した本人の手元にある。
3. 押しても本文の選択は解けないようにする。押下は `mousedown` + `preventDefault` で拾い、
   textarea からフォーカスを奪わない（綴り候補の `popButton` と同じやり方）。

## 方針（to-be）

`showTransText(message, isNote)` の後に、和訳のときだけコピーボタンを足す。

- ボタンは既存の `.copy-btn` クラスをそのまま使う（文言・押下後の "コピーしました" 表示・
  1.4 秒で戻る挙動も同じ）。位置は `.trans-pop` を `position: fixed` のまま
  相対位置の基準にして右上へ重ねる。文字と重ならないよう `.trans-pop` の右側に余白を足す。
- 押下は `mousedown` で拾い `preventDefault()` する。`copyText()` は既存の関数をそのまま呼ぶ
  （同じ IIFE 内なので関数宣言の巻き上げで参照できる）。
- 紙片を閉じる条件は変更しない。ボタンは `.trans-pop` の中にあるので、
  「ポップの外を押したら閉じる」判定（`transPop.contains(event.target)`）に自然と乗る。

## 影響範囲

| ファイル | 変更 |
| --- | --- |
| `backend/src/compositionView.ts` | `.trans-pop` の右余白、コピーボタンの生成（`showTransText`）|
| `backend/test/compositionView.test.ts` | 生成 HTML の検証を追加 |

サーバ側・DB・コスト集計は変更なし。

## テスト方針

- `compositionView.test.ts`: 和訳のときだけ `.copy-btn` を足すこと、`copyText` を呼ぶこと、
  `mousedown` + `preventDefault` で拾うこと。
- 手動（Playwright）: 和訳が出た紙片のボタンを押すとクリップボードに訳文が入り、
  本文の選択が解けないこと。案内文のときはボタンが出ないこと。
