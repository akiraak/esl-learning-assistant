# 選択翻訳の開始を、選択が固定されてから1秒後にする

## 目的・背景

執筆画面（`/admin/writing/:id`）の選択翻訳は、選択が変わってから **250ms** で翻訳を投げる
（`backend/src/compositionView.ts` の `transTimer = setTimeout(runTranslate, 250)`、
docs/plans/archive/writing-selection-translate.md）。

250ms は短く、読み返しながら選択範囲を伸ばしたり選び直したりしている途中で投げてしまい、
使わない訳のためにモデルを呼ぶことがある。選択が固定されたと言える間を空けてから始めたい。

## 決定事項

1. 待ち時間を 250ms → **1000ms** にする。
2. 数え方は今のまま「最後に選択が変わってから」。選択が動くたびにタイマーを引き直すので、
   ドラッグ中や shift+矢印で伸ばしている間は始まらず、手が止まって1秒で始まる。
3. 待っている間は紙片を出さない（今と同じ）。「翻訳しています…」は投げた後に出る。

## 方針（to-be）

`compositionView.ts` の待ち時間を名前付きの定数にして 1000 にする。

```js
// 選択が固定されたと見なすまでの待ち。伸ばしている途中では投げない
var TRANSLATE_DELAY_MS = 1000;
...
transTimer = setTimeout(runTranslate, TRANSLATE_DELAY_MS);
```

`onSelectionChanged` は毎回 `closeTransPop()`（＝`clearTimeout(transTimer)`）を通ってから
タイマーを張り直すので、数え直しの仕組みには手を入れない。

## 影響範囲

| ファイル | 変更 |
| --- | --- |
| `backend/src/compositionView.ts` | 待ち時間の定数化と 1000ms への変更 |
| `backend/test/compositionView.test.ts` | 待ち時間を見ている検証を更新 |

サーバ側・DB・コスト集計は変更なし。

## テスト方針

- `compositionView.test.ts`: `setTimeout(runTranslate, TRANSLATE_DELAY_MS)` と定数 1000。
- 手動（Playwright）: 選択して 0.6 秒では通信が起きず、1.2 秒後に和訳が出ること。
  選択を伸ばし続けている間は投げず、止めてから1秒で1回だけ投げること。
