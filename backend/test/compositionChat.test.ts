import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildChatPagesText,
  buildChatSystemPrompt,
  createTextFlusher,
  runChatStreamTurns,
  sanitizeChatHistory,
  CHAT_ALL_PAGES_MAX_LENGTH,
  CHAT_COMPOSITION_MAX_LENGTH,
  CHAT_HISTORY_MAX_MESSAGES,
  CHAT_PAUSE_TURN_MAX_RETRIES,
  CHAT_TOOLS,
  CHAT_WEB_SEARCH_MAX_USES,
  type ChatMessage,
  type ChatPage,
  type ChatStream,
} from "../src/compositionChat";
import type Anthropic from "@anthropic-ai/sdk";

// 執筆画面の相談チャット。import は Anthropic クライアントを構築するだけで通信しない
// （documentExtract.test.ts と同じ扱い）。ここではプロンプト組み立てだけを検証する。

/// 開いているページ1枚だけ（＝「全ページを含める」オフ）のときの渡し方。
function activePage(text: string): ChatPage[] {
  return [{ name: "", position: 1, english_text: text, active: true }];
}

/// タブ名と本文の組から ChatPage[] を作る。active は index 番目。
function pages(entries: Array<[string, string]>, activeIndex: number): ChatPage[] {
  return entries.map(([name, english_text], index) => ({
    name,
    position: index + 1,
    english_text,
    active: index === activeIndex,
  }));
}

test("システムプロンプト: 書いている英文を必ず含める（これがこのチャットの肝）", () => {
  const prompt = buildChatSystemPrompt(activePage("  I went to school yesterday and met my friend.  "));

  assert.match(prompt, /【学習者が書いている英文】/);
  assert.match(prompt, /I went to school yesterday and met my friend\./);
  // 前後の空白は落とす
  assert.doesNotMatch(prompt, /  I went/);
});

test("システムプロンプト: 本文が空でも「まだ書かれていない」ことを伝える", () => {
  const prompt = buildChatSystemPrompt(activePage("   \n  "));

  assert.match(prompt, /\(まだ何も書かれていません\)/);
});

test("システムプロンプト: 英文はコピーできるようコードブロックで示させる", () => {
  const prompt = buildChatSystemPrompt(activePage("I go to school yesterday."));

  // 画面側はこのブロックを1つのまとまりと見なしてコピーボタンを出す
  assert.match(prompt, /```/);
  assert.match(prompt, /修正後の英文・例文・言い換えは/);
});

test("システムプロンプト: 長すぎる本文は上限で切る", () => {
  const long = "a".repeat(CHAT_COMPOSITION_MAX_LENGTH + 500);
  const prompt = buildChatSystemPrompt(activePage(long));

  assert.equal(prompt.includes("a".repeat(CHAT_COMPOSITION_MAX_LENGTH)), true);
  assert.equal(prompt.includes("a".repeat(CHAT_COMPOSITION_MAX_LENGTH + 1)), false);
});

// --- 全ページの同梱（buildChatPagesText）----------------------------------
// 「全ページを含める」スイッチ（docs/plans/writing-chat-all-pages.md）で渡る形。

test("全ページ: 1ページだけなら見出しを付けず、従来どおり本文そのまま", () => {
  const text = buildChatPagesText(activePage("  I like cats.  "));

  assert.equal(text, "I like cats.");
});

test("全ページ: 各ページの見出しと本文が並び、開いているページに印が付く", () => {
  const text = buildChatPagesText(
    pages(
      [
        ["導入", "I have a dog."],
        ["本論", "He is very big."],
      ],
      1
    )
  );

  assert.match(text, /## 導入\nI have a dog\./);
  assert.match(text, /## 本論 ← いま開いているページ\nHe is very big\./);
  // 印は開いているページだけ
  assert.equal(text.match(/← いま開いているページ/g)?.length, 2, "前置きと見出しの2箇所だけ");
  // 前置きで、質問がどのページのものかを伝える
  assert.match(text, /この作文は複数のページに分かれています/);
});

test("全ページ: タブ名が空なら「ページ N」を見出しにする", () => {
  const text = buildChatPagesText(
    pages(
      [
        ["", "First."],
        ["", "Second."],
      ],
      0
    )
  );

  assert.match(text, /## ページ 1 ← いま開いているページ/);
  assert.match(text, /## ページ 2\nSecond\./);
});

test("全ページ: 空のページも「空」と分かる形で載せる（書き忘れを指摘できるように）", () => {
  const text = buildChatPagesText(
    pages(
      [
        ["導入", "I have a dog."],
        ["結び", "   "],
      ],
      0
    )
  );

  assert.match(text, /## 結び\n\(このページはまだ空です\)/);
});

test("全ページ: 1ページあたりは CHAT_COMPOSITION_MAX_LENGTH で切る", () => {
  const long = "a".repeat(CHAT_COMPOSITION_MAX_LENGTH + 500);
  const text = buildChatPagesText(pages([["長い", long], ["短い", "ok"]], 1));

  assert.equal(text.includes("a".repeat(CHAT_COMPOSITION_MAX_LENGTH)), true);
  assert.equal(text.includes("a".repeat(CHAT_COMPOSITION_MAX_LENGTH + 1)), false);
});

test("全ページ: 合計の上限を超えたら以降のページを落とし、省略した旨を書く", () => {
  const body = "b".repeat(CHAT_COMPOSITION_MAX_LENGTH);
  // 5000 字 × 6 ページ = 30000 字。合計上限（20000）に収まらない分が出る
  const entries: Array<[string, string]> = Array.from({ length: 6 }, (_, index) => [`ページ${index + 1}`, body]);
  const text = buildChatPagesText(pages(entries, 0));

  assert.ok(text.length <= CHAT_ALL_PAGES_MAX_LENGTH + 500, "上限の前後に収まる（前置きと注記の分だけ超える）");
  assert.match(text, /\(長さの上限のため、上記以外のページは省略しました\)/);
  assert.equal(text.includes("## ページ6"), false, "後ろのページから落ちる");
});

test("全ページ: 開いているページは末尾にあっても省略されない", () => {
  const body = "b".repeat(CHAT_COMPOSITION_MAX_LENGTH);
  const entries: Array<[string, string]> = Array.from({ length: 6 }, (_, index) => [`ページ${index + 1}`, body]);
  const text = buildChatPagesText(pages(entries, 5));

  assert.match(text, /## ページ6 ← いま開いているページ/);
  assert.match(text, /\(長さの上限のため、上記以外のページは省略しました\)/);
});

test("履歴: 空の発言を落とす", () => {
  const history: ChatMessage[] = [
    { role: "user", content: "質問1" },
    { role: "assistant", content: "  " },
    { role: "user", content: "質問2" },
  ];

  assert.deepEqual(sanitizeChatHistory(history), [
    { role: "user", content: "質問1" },
    { role: "user", content: "質問2" },
  ]);
});

test("履歴: 直近 CHAT_HISTORY_MAX_MESSAGES 件に丸め、user 始まりに揃える", () => {
  const history: ChatMessage[] = Array.from({ length: CHAT_HISTORY_MAX_MESSAGES + 6 }, (_, index) => ({
    role: index % 2 === 0 ? "user" : "assistant",
    content: `発言${index}`,
  }));

  const sanitized = sanitizeChatHistory(history);

  assert.ok(sanitized.length <= CHAT_HISTORY_MAX_MESSAGES);
  assert.equal(sanitized[0].role, "user");
  assert.equal(sanitized.at(-1)!.content, `発言${CHAT_HISTORY_MAX_MESSAGES + 5}`);
});

test("履歴: 先頭が assistant のときはそれを落とす（API は user 始まりを要求する）", () => {
  const history: ChatMessage[] = [
    { role: "assistant", content: "以前の返答" },
    { role: "user", content: "質問" },
  ];

  assert.deepEqual(sanitizeChatHistory(history), [{ role: "user", content: "質問" }]);
});

test("履歴: 空配列はそのまま空（初回の質問）", () => {
  assert.deepEqual(sanitizeChatHistory([]), []);
});

// --- 逐次表示の間引き（createTextFlusher）---------------------------------
// 生成中は delta が細かく届くが、1つごとに Markdown を組み直して送るのは無駄なので間引く。
// 「最初の1回はすぐ出る」「間隔内は溜める」「最後は必ず出る」が守れているかを見る。

function flusherWithClock(intervalMs = 80) {
  const emitted: string[] = [];
  let clock = 1000;
  const flusher = createTextFlusher((text) => emitted.push(text), {
    intervalMs,
    now: () => clock,
  });
  return { emitted, flusher, advance: (ms: number) => (clock += ms) };
}

test("間引き: 最初の push はすぐ通知する（待たせない）", () => {
  const { emitted, flusher } = flusherWithClock();

  flusher.push("こん");

  assert.deepEqual(emitted, ["こん"]);
});

test("間引き: 間隔内の push は溜め、間隔が空けば最新の全文を通知する", () => {
  const { emitted, flusher, advance } = flusherWithClock(80);

  flusher.push("こん");
  advance(10);
  flusher.push("こんに");
  advance(10);
  flusher.push("こんにち");
  assert.deepEqual(emitted, ["こん"], "間隔内は溜めるだけ");

  advance(80);
  flusher.push("こんにちは");

  // 途中の "こんに" / "こんにち" は飛ばし、最新の全文だけを送る
  assert.deepEqual(emitted, ["こん", "こんにちは"]);
});

test("間引き: flush で溜まっている分を必ず出す（最後の1回を落とさない）", () => {
  const { emitted, flusher, advance } = flusherWithClock(80);

  flusher.push("こん");
  advance(10);
  flusher.push("こんにちは");
  flusher.flush();

  assert.deepEqual(emitted, ["こん", "こんにちは"]);
});

test("間引き: 溜まっていなければ flush しても重複して出さない", () => {
  const { emitted, flusher } = flusherWithClock(80);

  flusher.push("こんにちは");
  flusher.flush();
  flusher.flush();

  assert.deepEqual(emitted, ["こんにちは"]);
});

// --- Web 検索（サーバーツール）--------------------------------------------
// docs/plans/writing-chat-web-search.md。実行は Anthropic 側なので、こちらで見るのは
// 「渡している道具」「検索させる方針」「pause_turn で積んで再送する」の3点。

test("検索: web_search / web_fetch をセットで渡す（web_fetch は会話に出た URL しか取れない）", () => {
  assert.deepEqual(
    CHAT_TOOLS.map((tool) => tool.type),
    ["web_search_20260209", "web_fetch_20260209"]
  );
  const search = CHAT_TOOLS[0] as Anthropic.Messages.WebSearchTool20260209;
  assert.equal(search.max_uses, CHAT_WEB_SEARCH_MAX_USES, "検索し放題にはしない");
});

test("システムプロンプト: 検索は必要なときだけ、使ったら出典を出させる", () => {
  const prompt = buildChatSystemPrompt(activePage("I went to a Sakura Matsuri last week."));

  assert.match(prompt, /web_search で調べる/);
  assert.match(prompt, /文法・語法・自然さの判断は自分の知識で答える/);
  assert.match(prompt, /出典を Markdown リンク/);
});

// --- pause_turn の積み直し（runChatStreamTurns）----------------------------

interface FakeTurn {
  text: string;
  stopReason: Anthropic.Message["stop_reason"];
  inputTokens?: number;
  outputTokens?: number;
  webSearchRequests?: number;
}

/// turns を順に返すスタブ。何を送ったか（sent）を残して、積み直しを検証できるようにする。
function fakeStarter(turns: FakeTurn[]) {
  const sent: Anthropic.Messages.MessageParam[][] = [];
  let index = 0;

  const start = (messages: Anthropic.Messages.MessageParam[]): ChatStream => {
    sent.push([...messages]);
    const turn = turns[Math.min(index, turns.length - 1)];
    index += 1;
    return {
      on(_event: "text", handler: (delta: string) => void) {
        handler(turn.text);
        return undefined;
      },
      async finalMessage() {
        return {
          content: [{ type: "text", text: turn.text, citations: null }] as Anthropic.ContentBlock[],
          stop_reason: turn.stopReason,
          usage: {
            input_tokens: turn.inputTokens ?? 0,
            output_tokens: turn.outputTokens ?? 0,
            server_tool_use: { web_search_requests: turn.webSearchRequests ?? 0, web_fetch_requests: 0 },
          } as Anthropic.Usage,
        };
      },
    };
  };

  return { start, sent, callCount: () => index };
}

test("pause_turn: 止まらなければ1回のリクエストで完結する", async () => {
  const fake = fakeStarter([{ text: "こう直すと自然です。", stopReason: "end_turn", inputTokens: 100, outputTokens: 20 }]);

  const result = await runChatStreamTurns(fake.start, [{ role: "user", content: "質問" }], () => {});

  assert.equal(fake.callCount(), 1);
  assert.equal(result.text, "こう直すと自然です。");
  assert.equal(result.resumedTurns, 0);
  assert.equal(result.truncated, false);
});

test("pause_turn: アシスタントのターンを積んで再送し、本文をつなげる", async () => {
  const fake = fakeStarter([
    { text: "調べています…", stopReason: "pause_turn", inputTokens: 100, outputTokens: 10, webSearchRequests: 3 },
    { text: "実際に使われている表現です。", stopReason: "end_turn", inputTokens: 400, outputTokens: 30 },
  ]);
  const emitted: string[] = [];

  const result = await runChatStreamTurns(fake.start, [{ role: "user", content: "質問" }], (text) =>
    emitted.push(text)
  );

  assert.equal(fake.callCount(), 2);
  assert.equal(result.text, "調べています…実際に使われている表現です。", "ターンをまたいで本文をつなげる");
  assert.equal(result.resumedTurns, 1);
  assert.equal(result.truncated, false);
  // 再送は「元の messages ＋ 途中までのアシスタントのターン」
  assert.equal(fake.sent[0].length, 1);
  assert.equal(fake.sent[1].length, 2);
  assert.equal(fake.sent[1][1].role, "assistant");
  // 再送のぶんも足し合わせる（入力は再送のたびに再課金される）
  assert.equal(result.inputTokens, 500);
  assert.equal(result.outputTokens, 40);
  assert.equal(result.webSearchRequests, 3);
  assert.equal(emitted.at(-1), result.text, "最後の通知は全文");
});

test("pause_turn: 再送の上限に達したら打ち切り、途中までを truncated 付きで返す", async () => {
  const fake = fakeStarter([{ text: "…", stopReason: "pause_turn", inputTokens: 10, outputTokens: 1 }]);

  const result = await runChatStreamTurns(fake.start, [{ role: "user", content: "質問" }], () => {});

  assert.equal(fake.callCount(), CHAT_PAUSE_TURN_MAX_RETRIES + 1, "無限ループにしない");
  assert.equal(result.resumedTurns, CHAT_PAUSE_TURN_MAX_RETRIES);
  assert.equal(result.truncated, true);
  assert.equal(result.text, "…".repeat(CHAT_PAUSE_TURN_MAX_RETRIES + 1));
});
