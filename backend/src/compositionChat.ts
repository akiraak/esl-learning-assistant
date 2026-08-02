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

export async function generateChatReply(
  compositionText: string,
  history: ChatMessage[],
  question: string
): Promise<ChatReplyResult> {
  const messages: Anthropic.Messages.MessageParam[] = [
    ...sanitizeChatHistory(history).map((message) => ({
      role: message.role,
      content: message.content,
    })),
    { role: "user" as const, content: question },
  ];

  const response = await client.messages.create({
    model: config.writingChatModel,
    max_tokens: 2048,
    thinking: { type: "disabled" },
    system: buildChatSystemPrompt(compositionText),
    messages,
  });

  const text = response.content
    .filter((block): block is Anthropic.Messages.TextBlock => block.type === "text")
    .map((block) => block.text)
    .join("\n")
    .trim();

  if (!text) {
    throw new Error("Claude APIからテキスト応答が得られませんでした");
  }

  return {
    text,
    model: config.writingChatModel,
    inputTokens: response.usage.input_tokens,
    outputTokens: response.usage.output_tokens,
  };
}
