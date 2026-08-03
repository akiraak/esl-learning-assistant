import Anthropic from "@anthropic-ai/sdk";
import { config } from "./config";

// 執筆画面（/admin/writing/:id）の右ペインで動く、書いている英文についての相談チャット。
// 質問には必ず「いま紙に書かれている英文」をプロンプトへ含めるので、学習者は本文を貼らずに
// 「この文は自然？」「この単語で合っている？」と聞ける。

const client = new Anthropic({ apiKey: config.anthropicApiKey });

/// 1通の発言。DB の composition_chat_messages と対応する。
export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export const CHAT_MESSAGE_MAX_LENGTH = 2000;
/// AI に渡す過去の発言数の上限（トークン肥大を防ぐため直近のみ。1往復＝2通）
export const CHAT_HISTORY_MAX_MESSAGES = 20;
/// プロンプトに載せる英文の上限（本文と同じ上限。これを超える分は末尾を切る）
export const CHAT_COMPOSITION_MAX_LENGTH = 5000;

const NO_TEXT_PLACEHOLDER = "(まだ何も書かれていません)";

/// システムプロンプト。学習者が書いている英文を常に同梱するのがこのチャットの肝。
/// 本文が空でもプレースホルダを入れ、「まだ書いていない」ことを AI に伝える。
export function buildChatSystemPrompt(compositionText: string): string {
  const trimmed = compositionText.trim().slice(0, CHAT_COMPOSITION_MAX_LENGTH);
  return [
    `あなたはESL学習者の英作文を隣で手伝うライティング講師です。`,
    `学習者はいま次の英文を書いています（書きかけのこともあります）。`,
    `学習者の質問は、特に断りがなければこの英文についてのものとして答えてください。`,
    ``,
    `【学習者が書いている英文】`,
    trimmed || NO_TEXT_PLACEHOLDER,
    ``,
    `回答の方針:`,
    `- 日本語で、短く具体的に答える（要点が複数あるときは Markdown の箇条書き）`,
    `- 英語の例文・言い換え・修正案は英語のまま示し、なぜそうなるかを日本語で説明する`,
    // 画面側は ``` のブロックを「そのままコピーできる英文」として扱い、コピーボタンを出す。
    `- 修正後の英文・例文・言い換えは、学習者がそのまま写せるよう \`\`\` で囲んだブロックに英文だけを入れる`,
    `  （日本語の説明はブロックの外に書く）`,
    `- 全文の書き直しは頼まれたときだけ。まずは直す箇所と理由を示し、学習者が自分で直せるようにする`,
    `- 英文がまだ空のときは、書き出し方や使えそうな表現を提案する`,
  ].join("\n");
}

/// 直近 CHAT_HISTORY_MAX_MESSAGES 件に丸め、空の発言を落とす。
/// 先頭が assistant にならないよう（API が user 始まりを要求する）調整する。
export function sanitizeChatHistory(messages: ChatMessage[]): ChatMessage[] {
  const recent = messages
    .filter((message) => message.content.trim() !== "")
    .slice(-CHAT_HISTORY_MAX_MESSAGES);
  const firstUser = recent.findIndex((message) => message.role === "user");
  return firstUser <= 0 ? recent : recent.slice(firstUser);
}

export interface ChatReplyResult {
  text: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

/// 逐次表示で途中経過を通知する間隔。delta 1つごとに Markdown を組み直すのは無駄なので、
/// この間隔まで通知を間引く（最後の1回は flush() で必ず流す）。
export const CHAT_STREAM_FLUSH_INTERVAL_MS = 80;

export interface TextFlusher {
  /// 最新の全文を渡す。前回の通知から間隔が空いていれば emit する
  push(text: string): void;
  /// 間引きで保留になっている分があれば emit する
  flush(): void;
}

/// push された全文を一定間隔でだけ emit する間引き器。
/// now を差し替えられるようにしてあるのはテストのため。
export function createTextFlusher(
  emit: (text: string) => void,
  options: { intervalMs?: number; now?: () => number } = {}
): TextFlusher {
  const intervalMs = options.intervalMs ?? CHAT_STREAM_FLUSH_INTERVAL_MS;
  const now = options.now ?? Date.now;
  let lastEmittedAt = Number.NEGATIVE_INFINITY;
  let pending: string | null = null;

  return {
    push(text: string) {
      if (now() - lastEmittedAt < intervalMs) {
        pending = text;
        return;
      }
      lastEmittedAt = now();
      pending = null;
      emit(text);
    },
    flush() {
      if (pending === null) return;
      const text = pending;
      pending = null;
      lastEmittedAt = now();
      emit(text);
    },
  };
}

export interface ChatReplyStreamOptions {
  /// 途中経過。そこまでに届いた全文が渡る（間引き済み）
  onText: (fullText: string) => void;
  /// 画面が閉じられたときなど、生成を打ち切るための signal
  signal?: AbortSignal;
}

function buildChatMessages(history: ChatMessage[], question: string): Anthropic.Messages.MessageParam[] {
  return [
    ...sanitizeChatHistory(history).map((message) => ({
      role: message.role,
      content: message.content,
    })),
    { role: "user" as const, content: question },
  ];
}

/// 生成の進みに合わせて onText へ「そこまでの全文」を渡し、
/// 完了したら ChatReplyResult（保存・課金ログ用）を返す。
/// 途中で signal が中断されたら例外になるので、呼び出し側は保存しないこと。
export async function generateChatReplyStream(
  compositionText: string,
  history: ChatMessage[],
  question: string,
  options: ChatReplyStreamOptions
): Promise<ChatReplyResult> {
  const messages = buildChatMessages(history, question);

  const stream = client.messages.stream(
    {
      model: config.writingChatModel,
      max_tokens: 2048,
      thinking: { type: "disabled" },
      system: buildChatSystemPrompt(compositionText),
      messages,
    },
    { signal: options.signal }
  );

  let text = "";
  const flusher = createTextFlusher(options.onText);
  stream.on("text", (delta) => {
    text += delta;
    flusher.push(text);
  });

  const final = await stream.finalMessage();
  flusher.flush();

  const trimmed = text.trim();
  if (!trimmed) {
    throw new Error("Claude APIからテキスト応答が得られませんでした");
  }

  return {
    text: trimmed,
    model: config.writingChatModel,
    inputTokens: final.usage.input_tokens,
    outputTokens: final.usage.output_tokens,
  };
}
