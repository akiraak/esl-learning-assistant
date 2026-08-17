# 管理画面の音声再生を画面下部の大きなプレイヤーに集約する

## 目的・背景

管理画面の音声再生は、表の各行に `<audio controls>` を 220x32px で埋め込んでいる。
このサイズだとブラウザ標準プレイヤーのシークバーが数十 px しかなく、
つまんで動かせない・狙った位置に飛べない。文字起こしログ（数分の音声）や
TTS 一覧の確認では「途中まで飛ばして聞く」ができず実用にならない。

行ごとに大きなプレイヤーを置くと表が崩れるので、**再生は画面下部に固定した
1 つの大きなプレイヤー（ドックプレイヤー）に集約**し、表の各行は「▶ 再生」
ボタンだけにする。行から再生を押すとドックに読み込まれて再生が始まり、
シーク・早送り・速度変更はドック側の大きな UI で操作する。

現状の `<audio controls>` の設置箇所（すべて `backend/src/admin.ts`）:

| 画面 | 該当行 | src |
| --- | --- | --- |
| 単語詳細 `/admin/words/:id` の読み上げ音声 | `admin.ts:1699` | `/admin/tts/:id/audio` |
| TTS 一覧 `/admin/tts` | `admin.ts:1903` | `/admin/tts/:id/audio` |
| 文字起こしログ `/admin/transcriptions` | `admin.ts:2455` | `/admin/transcriptions/:id/audio` |
| 単語クイズ詳細 `/admin/quiz-questions/item`（`quizAudioCell`） | `admin.ts:2841` | `/admin/tts/:id/audio` |
| コンテンツファイル `/admin/content-files`（音声拡張子のみ） | `admin.ts:3069` | `/admin/content-files/file?...` |

配信側はいずれも `res.sendFile` なので Range リクエスト（シーク）は既に効く。
サーバ側の変更は不要で、今回は描画（HTML/CSS/JS）だけの話。

## 対応方針

### Phase 1: 共通ドックプレイヤーを `renderPage` に追加する

- `PAGE_STYLE` にドックのスタイルを足す（既存のダークテーマの配色トークンを流用）
  - `position: fixed; left/right/bottom: 0;` の帯。サイドバーの上に重ねる（`z-index`）
  - 既定は非表示（`hidden` 属性）。最初の再生でだけ出す
  - 表示中は `main` の下端に padding を足して、最終行がドックに隠れないようにする
- `renderPage()` の `<body>` 末尾にドックのマークアップとインライン `<script>` を出力する
  - 引数は増やさず全ページに出す（非表示なので実害なし。`compositionView.ts` に
    先例があるとおりインライン script は既存パターン）
- ドックの中身
  - 大きな再生／一時停止ボタン（44px 角）
  - **シークバー**: 横幅いっぱいの `input[type=range]`。トラック 8px・つまみ 18px・
    当たり判定 28px（`::-webkit-slider-thumb` / `::-moz-range-thumb` を指定）。
    ドラッグ中は `input` で表示だけ更新し、`change` で `currentTime` を確定する
  - 5 秒戻す / 5 秒進むボタン
  - 経過時間 / 全体長（`mono`。メタデータ読み込み前は `--:--`）
  - 再生速度の切り替え（0.75 / 1.0 / 1.25 / 1.5 を巡回）
  - いま再生中の対象名（単語・ファイル名・ログ #ID など）
  - 閉じるボタン（停止してドックを隠す）
- キーボード操作（`input` / `textarea` にフォーカスがあるときは無効）
  - Space: 再生／一時停止（ページスクロールは `preventDefault`）
  - ← / →: 5 秒シーク
- 再生中の行を見失わないよう、押した再生ボタンに `.playing` を付けて色を変える

### Phase 2: 各画面の `<audio controls>` を再生ボタンに差し替える

- ヘルパー `audioPlayButton(src: string, label: string): string` を `admin.ts` に追加し、
  `<button type="button" class="play-btn" data-audio-src="…" data-audio-title="…">▶ 再生</button>`
  を返す（属性値は `escapeHtml` を通す。`type="button"` で削除フォームの誤送信を防ぐ）
- 上表の 5 箇所を置き換える。ラベルは画面ごとに分かりやすいものを渡す
  - 単語詳細: 単語（`row.word`）
  - TTS 一覧: `#id` + テキスト先頭
  - 文字起こしログ: タイトル（無ければ `#id`）
  - クイズ詳細: `audioText` の先頭
  - コンテンツファイル: ファイル名
- 「音声なし」「未合成」の表示は現状どおり据え置く

### Phase 3: 動作確認

- `cd backend && npm run build`（tsc）
- `npm run dev` でローカル起動し、5 画面を curl して
  `<audio controls>` が残っていないこと・`data-audio-src` が正しいことを確認する
- ブラウザで実際に再生・シーク（ドラッグと途中クリック）・速度変更・
  キーボード操作を確認する。特に文字起こしログの長い音声で狙った位置に飛べること
- スマホ幅（`max-width: 720px`）でドックが 2 段に折り返して操作できること

## 影響範囲

- `backend/src/admin.ts` のみ（`PAGE_STYLE` / `renderPage` / 5 箇所の描画）
- 新規エンドポイントなし。DB 変更なし。iOS 側の変更なし
- 既存の音声配信エンドポイントはそのまま使う（Range 対応済み）

## 決めたこと・注意点

- **JS 前提にする**: ローカル開発用の管理画面なので no-JS フォールバック（`<noscript>` に
  従来の `<audio controls>` を出す等）は入れない
- **プリロードは増やさない**: 現状も `preload="none"` なので、ボタン化しても
  クリックするまで音声は取りに行かない（ドックの `<audio>` は 1 つだけ生成し、
  再生のたびに `src` を差し替える）
- 再生中の音声を削除フォームで消した場合はリダイレクトでページが再描画され、
  ドックも初期状態に戻る（特別な後始末は不要）

## テスト方針

- 自動テスト: `backend/test/` は API ロジック中心で管理画面 HTML のテストは無いため、
  今回も追加しない（`npm run build` の型チェックまで）
- 手動: Phase 3 のとおりブラウザで再生・シーク操作を確認する
