# 相談チャットに Web 検索を入れる

## 目的・背景

執筆画面（/admin/writing/:id）右ペインの相談チャット（`backend/src/compositionChat.ts`）は、
現在 `tools` を渡していないため、モデルの内部知識だけで答えている。

- 「この言い回しは実際に使われるのか」「最近の固有名詞・時事的な話題の綴りや用法」など、
  学習者の質問には最新の実例を当たった方が確実なものがある。
- 使用モデル `claude-sonnet-5` は Anthropic 側で実行されるサーバーツール
  `web_search_20260209` / `web_fetch_20260209` に対応しているので、
  こちらで検索処理を実装する必要はなく `tools` を足すだけで有効化できる。

## 対応方針

`generateChatReplyStream`（`backend/src/compositionChat.ts:198`）の
`client.messages.stream` に `tools` を追加する。

```ts
tools: [
  { type: "web_search_20260209", name: "web_search", max_uses: 3 },
  { type: "web_fetch_20260209", name: "web_fetch" },
]
```

`web_fetch` は「会話にすでに出ている URL」しか取りに行けないため、
`web_search` とセットで入れて初めて意味を持つ。

### 検討事項

- **いつ検索させるか**: 添削寄りの質問（文法・自然さ）で毎回検索されるとコストと待ち時間が
  無駄になる。`buildChatSystemPrompt` に「用例・時事・固有名詞の確認が要るときだけ検索する」
  旨の方針を1行足すか、`max_uses` を小さく抑えるかで制御する。
- **出典を返すか**: 検索結果には引用元 URL が付く。学習者に見せるか（Markdown リンク）、
  黙って参考にするだけにするかを決める。

## 影響範囲

- `backend/src/compositionChat.ts`
  - `tools` の追加。
  - **`stop_reason: "pause_turn"` の処理**。サーバーツールはサーバー側でループし、
    上限に達すると `pause_turn` で止まる。現在は 1 回の stream で完結する前提なので、
    そのままだと応答が途中で切れたまま保存されてしまう。
    アシスタントのターンを `messages` に積んで再リクエストするループが要る
    （再試行回数の上限も設ける）。
  - `stream.on("text")` だけで本文を組み立てている箇所の確認。応答には
    `server_tool_use` / `web_search_tool_result` ブロックが混ざるようになる。
- 課金ログ: `ChatReplyResult` は `inputTokens` / `outputTokens` のみ。Web 検索は
  トークンとは別に検索回数ぶんの課金があるため、`usage` から検索回数を拾って
  記録するかを決める（`backend/src/pricing.ts` の扱いも合わせて要検討）。
- 画面側（`compositionView.ts`）: 出典を出すなら表示の追加。出さないなら変更なし。

## テスト方針

- `backend/test/` に既存のチャット系テストがあるので、そこに合わせる。
- `tools` を渡していること、システムプロンプトに検索方針の行が入ることを単体で確認。
- `pause_turn` のループは、`stop_reason` を返すスタブで「積んで再送する」ことを確認。
- 実 API での手動確認: 検索が要る質問（最近の固有名詞など）と要らない質問（文法）を
  1問ずつ投げ、後者で検索が走らないこと・応答が途中で切れないことを見る。

## Phase

- Phase 1: `tools` 追加 + `pause_turn` ループ + テスト
- Phase 2: システムプロンプトでの検索方針の調整、出典表示の要否を決めて実装
- Phase 3: 課金ログへの検索回数の反映
