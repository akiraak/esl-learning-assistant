# 執筆画面のタブ列「＋」を小さくする

## 目的・背景

執筆画面（管理画面の作文編集）のページタブ列にある「＋」（ページ追加）が、hover 時の地色と枠線が
タブ列の右端まで伸びてしまい、幅いっぱいの帯のように見える。ボタンは文字ぶんの小さなサイズに見せたい。

## 対応方針

`backend/src/compositionView.ts` の `.tab-add` を、文字ぶんの小さな正方形に固定する。

- `width: 26px; height: 26px; padding: 0` + `display: inline-flex` の中央寄せで「＋」を置く
- `margin-right: auto` でタブ列の余りをマージン側に吸わせ、地色が右端まで伸びないようにする
- `flex: 0 0 auto` / `box-sizing: border-box` で伸縮と枠線ぶんのはみ出しを止める

## 影響範囲

- `backend/src/compositionView.ts` の CSS のみ。HTML 構造・スクリプト（`renderTabs`）は変更なし。

## テスト方針

- `npm test`（`backend/test/compositionView.test.ts` の `tab-add` の disabled 判定が壊れないこと）
- `npx tsc --noEmit`
- 執筆画面を開いて、「＋」が小さな四角で、hover の地色が右端まで伸びないことを目視確認する

## 追記: タブ列の右側に出る明るい帯を消す（2026-08-02）

「＋」を小さくしても、タブが無い右側に地色より明るい帯（角に影の縁が付いた四角）が残っていた。
原因は影の付け先で、`.paper-stack`（タブ列＋紙）に `box-shadow` を持たせていたため、
影が落ちないのはその四角の内側＝タブ列の右側の空白まで含まれ、周りの机（影で少し暗い）との
差でそこだけ明るい帯に見えていた。

対応:

- `box-shadow` を `.paper-stack` から `.sheet`（紙）へ移し、タブ列を影の四角の外に出す
- `.tabs` に `position: relative; z-index: 1` を付け、紙の影がタブの下辺に掛からないようにする
- `@media (max-width: 720px)` と `@media print` の `box-shadow: none` も `.sheet` 側へ移す
- テスト（`タブ: 選択中のタブは紙と同じ地色で下辺が無く、影は紙だけが落とす`）の期待も入れ替える
