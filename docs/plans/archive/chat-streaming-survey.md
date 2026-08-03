# 調査: 作文チャットの AI 返答を逐次表示できるか

## 目的・背景

`/admin/writing/:id` の右ペインのチャットは、いま返答が**出来上がってから一度に**表示される。
返答が長いと「考え中…」のまま 10 秒以上待つことになり、動いているのか分からない。
返答の生成に合わせて文字を流したい。あわせて Markdown 表示が壊れないかを確認する。

## 現状（調査結果）

- 生成: `backend/src/compositionChat.ts:77` `client.messages.create(...)`（非ストリーミング）
  - モデルは `config.writingChatModel`（既定 `claude-sonnet-5`）、`max_tokens: 2048`、`thinking: {type:"disabled"}`
- エンドポイント: `backend/src/admin.ts:1089` `POST /admin/writing/:id/chat`
  - 成功後に user / assistant の 2 行を `insertCompositionChatMessage` で保存（課金ログも兼ねる）
  - `admin.ts:1136` `res.json({ replyHtml: renderCompositionMarkdown(result.text) })`
    → **Markdown → HTML の変換はサーバ側**（`marked` v18、`compositionView.ts:17`）
    → HTML エスケープしてから `marked.parse` するのが XSS 対策
- 画面: `backend/src/compositionView.ts` がサーバで HTML 文字列を組み立てる素の JS
  - `compositionView.ts:1458` で `fetch` → 返ってきた `replyHtml` を
    プレースホルダ吹き出しの `innerHTML` にまるごと差し込む（`:1479` 付近）
  - `decorateCopyTargets`（`:1383`）が `pre` / `blockquote` にコピーボタンを足す
- ストリーミングは**バックエンドに前例なし**（`text/event-stream` は vendored の vibeboard のみ）
- `backend/src/index.ts` に compression ミドルウェアは入っていない（`express.json` のみ）

## 結論

**できる。** SDK は `client.messages.stream()` を持ち、Express 側は chunked のレスポンスを
そのまま流せる。Markdown も、下記の方式なら表示は壊れない。

## 対応方針（案）

### 転送方式: fetch + chunked NDJSON（EventSource は使わない）

画面側は既に `fetch` の POST。`EventSource` は POST できないので、
`response.body.getReader()` で読む方式が素直。1 行 1 JSON（NDJSON）で

- `{"t":"delta","html":"..."}` … 途中経過
- `{"t":"done","html":"...","messageId":n}` … 確定
- `{"t":"error","message":"..."}`

を流す。SSE 形式（`text/event-stream`）にしても良いが、POST で使う以上
`EventSource` の恩恵はないので NDJSON の方が薄く済む。
プロキシ対策に `Cache-Control: no-cache` / `X-Accel-Buffering: no` を付け、
`res.flushHeaders()` してから書き始める。

### Markdown: 「毎回サーバで全文を再変換」で送る

差分テキストだけ送って画面側で Markdown を組み立てる案もあるが、
それには**ブラウザ用の Markdown パーサを新しく持ち込む必要がある**（今は `marked` がサーバ専用）。
エスケープ→`marked.parse` の XSS 対策も二重管理になる。

代わりに、蓄積した全文をサーバで毎回 `renderCompositionMarkdown` に通し、
出来た HTML を丸ごと送って `innerHTML` を差し替える。

- パーサが 1 つのままで済み、XSS 対策も現状のまま
- 常に全文を parse するので、途中の Markdown が壊れて見えることがない
- 返答は最大 2048 トークン（数 KB）。ローカル開発用なので全文再送のコストは問題にならない

ただし delta ごとに parse すると無駄なので、**~80ms 間隔で間引く**（最後は必ず送る）。

### Markdown の途中状態について（確認事項）

- 開いたままの ``` ` ``` フェンス → `marked` は閉じたものとして code ブロックに整形するので崩れない
- 書きかけの `**bold` / `- ` → その時点では素のテキストとして出て、続きが来た瞬間に整う
  （気になるなら「最後の未確定行は流さない」という間引きも足せる）
- **コピーボタン（`decorateCopyTargets`）は `done` のときだけ実行する。**
  途中で呼ぶとボタンが重複して増える。

### 保存・課金ログ

- いまは「成功したら 2 行 insert」。ストリーミングでも同じく**ストリーム完了後に insert** する
  （`stream.finalMessage()` の `usage` からトークン数が取れる）
- 途中で切断／中断されたときは保存しない。`req.on("close")` で `stream.abort()`

### 影響範囲

- `backend/src/compositionChat.ts` … `generateChatReplyStream()` を追加（既存関数は残す）
- `backend/src/admin.ts` … `POST /admin/writing/:id/chat` をストリーム応答に変更
- `backend/src/compositionView.ts` … `fetch` の後処理を reader ループに変更、
  `decorateCopyTargets` の呼び出し位置を `done` へ
- DB スキーマ変更なし。iOS アプリは無関係。

### テスト方針

- `backend/test/` に `generateChatReplyStream` の分割・結合のテスト（SDK はモック）
- 手動: 長めの返答を出す質問で、文字が流れること／``` ブロックが整形されること／
  コピーボタンが 1 個だけ付くこと／途中でタブを閉じても DB にゴミが残らないこと

## Phase

- Phase 1: バックエンドをストリーミング化（`compositionChat.ts` / `admin.ts`）
- Phase 2: 画面側の受信・逐次描画（`compositionView.ts`）
- Phase 3: 中断・エラー処理と手動確認
