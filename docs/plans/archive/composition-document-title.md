# 執筆画面のブラウザタブに作文タイトルを出す

## 目的・背景

管理画面の執筆画面（`/admin/writing/:id`）の `<title>` は `作文 #12` 固定で、
複数タブで作文を開いていると、どのタブで何を書いているのか分からない。
作文のタイトル（無ければ本文の先頭）をタブに出して見分けられるようにする。

## 対応方針

- `compositionView.ts` に `compositionDocumentTitle()` を追加する
  - 優先順位: タイトル → 選択中ページ本文の先頭 → `作文 #<id>`
  - 空白は 1 行にまとめ、長い場合は `…` で切る（既定 40 文字）
- `renderCompositionEditorPageHtml()` の `<title>` をこの関数の値にする
- タイトル欄の編集・「本文から生成」・本文入力で `document.title` を追従させる
  （サーバ側と同じ規則を JS 側にも小さく持つ）

## 影響範囲

- `backend/src/compositionView.ts` のみ（表示層）。DB・API は変更なし。

## テスト方針

- `backend/test/compositionView.test.ts` に `compositionDocumentTitle` の単体テストを追加
  （タイトルあり／空欄で本文から／どちらも空で `作文 #id`／長い場合の切り詰め）
- 執筆画面 HTML に期待する `<title>` が含まれることを確認する
- `npm test` を通す
