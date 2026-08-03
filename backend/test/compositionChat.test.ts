import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildChatSystemPrompt,
  createTextFlusher,
  sanitizeChatHistory,
  CHAT_COMPOSITION_MAX_LENGTH,
  CHAT_HISTORY_MAX_MESSAGES,
  type ChatMessage,
} from "../src/compositionChat";

// 執筆画面の相談チャット。import は Anthropic クライアントを構築するだけで通信しない
// （documentExtract.test.ts と同じ扱い）。ここではプロンプト組み立てだけを検証する。

test("システムプロンプト: 書いている英文を必ず含める（これがこのチャットの肝）", () => {
  const prompt = buildChatSystemPrompt("  I went to school yesterday and met my friend.  ");

  assert.match(prompt, /【学習者が書いている英文】/);
  assert.match(prompt, /I went to school yesterday and met my friend\./);
  // 前後の空白は落とす
  assert.doesNotMatch(prompt, /  I went/);
});

test("システムプロンプト: 本文が空でも「まだ書かれていない」ことを伝える", () => {
  const prompt = buildChatSystemPrompt("   \n  ");

  assert.match(prompt, /\(まだ何も書かれていません\)/);
});

test("システムプロンプト: 英文はコピーできるようコードブロックで示させる", () => {
  const prompt = buildChatSystemPrompt("I go to school yesterday.");

  // 画面側はこのブロックを1つのまとまりと見なしてコピーボタンを出す
  assert.match(prompt, /```/);
  assert.match(prompt, /修正後の英文・例文・言い換えは/);
});

test("システムプロンプト: 長すぎる本文は上限で切る", () => {
  const long = "a".repeat(CHAT_COMPOSITION_MAX_LENGTH + 500);
  const prompt = buildChatSystemPrompt(long);

  assert.equal(prompt.includes("a".repeat(CHAT_COMPOSITION_MAX_LENGTH)), true);
  assert.equal(prompt.includes("a".repeat(CHAT_COMPOSITION_MAX_LENGTH + 1)), false);
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
