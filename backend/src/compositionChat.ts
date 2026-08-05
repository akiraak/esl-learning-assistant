import Anthropic from "@anthropic-ai/sdk";
import { pageDisplayName } from "./composition";
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

/// 全ページを同梱するとき、プロンプトに載せる本文の合計上限。
/// 1ページあたりは従来どおり CHAT_COMPOSITION_MAX_LENGTH で切り、合計がこれを超える分は
/// ページ単位で落とす（docs/plans/writing-chat-all-pages.md）。
export const CHAT_ALL_PAGES_MAX_LENGTH = 20000;

/// Web 検索（Anthropic 側で走るサーバーツール）の1回の質問あたりの上限。
/// 文法・自然さの相談で毎回検索されると待ち時間も課金も無駄なので小さく抑える。
export const CHAT_WEB_SEARCH_MAX_USES = 3;
/// web_fetch は「会話にすでに出ている URL」しか取りに行けないので、検索より更に少なくてよい。
export const CHAT_WEB_FETCH_MAX_USES = 2;

/// 相談チャットに渡すサーバーツール。実行は Anthropic 側で完結するので、こちらに実装は要らない。
export const CHAT_TOOLS: Anthropic.Messages.ToolUnion[] = [
  { type: "web_search_20260209", name: "web_search", max_uses: CHAT_WEB_SEARCH_MAX_USES },
  { type: "web_fetch_20260209", name: "web_fetch", max_uses: CHAT_WEB_FETCH_MAX_USES },
];

/// stop_reason: "pause_turn"（サーバーツールのループが上限に達した合図）で
/// アシスタントのターンを積んで再送する回数の上限。無限ループにしないための歯止め。
export const CHAT_PAUSE_TURN_MAX_RETRIES = 3;

const NO_TEXT_PLACEHOLDER = "(まだ何も書かれていません)";
const EMPTY_PAGE_PLACEHOLDER = "(このページはまだ空です)";
const ACTIVE_PAGE_MARK = "← いま開いているページ";
const OMITTED_NOTE = "(長さの上限のため、上記以外のページは省略しました)";
/// 複数ページを並べたときの前置き。指示語（「この文は」）が開いているページに向くようにする。
const MULTI_PAGE_LEAD =
  `この作文は複数のページに分かれています。` +
  `特に断りがなければ「${ACTIVE_PAGE_MARK}」と印の付いたページについての質問として答えてください` +
  `（他のページは前後の流れを見るための材料です）。`;

/// 全ページ同梱のときにプロンプトへ渡す1ページ分。
export interface ChatPage {
  /// タブ名。空文字なら position から「ページ N」を作る
  name: string;
  /// 1 始まりのタブの並び順
  position: number;
  english_text: string;
  /// いま開いている（質問の主語になる）ページか
  active: boolean;
}

/// 複数ページを、プロンプトに載せる1つの本文へ畳む。
/// 1ページだけのときは見出しを付けず、従来の「本文そのまま」と同じ形にする。
/// 上限を超えた分はページ単位で落とし、落としたことを本文の末尾に明記する（黙って切らない）。
/// 開いているページは、それが末尾にあっても落ちないよう先に枠を取る。
export function buildChatPagesText(pages: ChatPage[]): string {
  if (pages.length <= 1) {
    return (pages[0]?.english_text ?? "").trim().slice(0, CHAT_COMPOSITION_MAX_LENGTH);
  }

  const sections = pages.map((page) => {
    const heading = `## ${pageDisplayName(page.name, page.position)}${page.active ? ` ${ACTIVE_PAGE_MARK}` : ""}`;
    const text = page.english_text.trim().slice(0, CHAT_COMPOSITION_MAX_LENGTH);
    return { active: page.active, block: `${heading}\n${text || EMPTY_PAGE_PLACEHOLDER}` };
  });

  // 開いているページの分を先に引いてから、残りを上から詰める
  const activeLength = sections.find((section) => section.active)?.block.length ?? 0;
  let budget = CHAT_ALL_PAGES_MAX_LENGTH - activeLength;
  const kept: string[] = [];
  let omitted = false;
  for (const section of sections) {
    if (section.active) {
      kept.push(section.block);
      continue;
    }
    if (section.block.length > budget) {
      omitted = true;
      continue;
    }
    budget -= section.block.length;
    kept.push(section.block);
  }

  const blocks = omitted ? [...kept, OMITTED_NOTE] : kept;
  return [MULTI_PAGE_LEAD, ...blocks].join("\n\n");
}

/// システムプロンプト。学習者が書いている英文を常に同梱するのがこのチャットの肝。
/// 渡すページは1枚（開いているページだけ）でも全ページでもよく、本文の組み立ては
/// buildChatPagesText に任せる。全ページが空でもプレースホルダを入れ、
/// 「まだ書いていない」ことを AI に伝える。
export function buildChatSystemPrompt(pages: ChatPage[]): string {
  const body = buildChatPagesText(pages);
  return [
    `あなたはESL学習者の英作文を隣で手伝うライティング講師です。`,
    `学習者はいま次の英文を書いています（書きかけのこともあります）。`,
    `学習者の質問は、特に断りがなければこの英文についてのものとして答えてください。`,
    ``,
    `【学習者が書いている英文】`,
    body || NO_TEXT_PLACEHOLDER,
    ``,
    `回答の方針:`,
    `- 日本語で、短く具体的に答える（要点が複数あるときは Markdown の箇条書き）`,
    `- 英語の例文・言い換え・修正案は英語のまま示し、なぜそうなるかを日本語で説明する`,
    // 画面側は ``` のブロックを「そのままコピーできる英文」として扱い、コピーボタンを出す。
    `- 修正後の英文・例文・言い換えは、学習者がそのまま写せるよう \`\`\` で囲んだブロックに英文だけを入れる`,
    `  （日本語の説明はブロックの外に書く）`,
    `- 全文の書き直しは頼まれたときだけ。まずは直す箇所と理由を示し、学習者が自分で直せるようにする`,
    `- 英文がまだ空のときは、書き出し方や使えそうな表現を提案する`,
    // Web 検索は Anthropic 側のサーバーツール。文法・自然さの相談で毎回走ると待ち時間と課金が無駄なので、
    // 「自分の知識で答えられないとき」に絞らせる（docs/plans/writing-chat-web-search.md）。
    `- 文法・語法・自然さの判断は自分の知識で答える。実際の用例の確認、時事・固有名詞・最新の情報が要るときだけ web_search で調べる`,
    `- 調べた内容を答えに使ったときは、出典を Markdown リンク（[サイト名](URL)）で答えの末尾に添える`,
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
  /// pause_turn での再送を含めた合計（再送のたびに入力は再課金されるので足し合わせる）
  inputTokens: number;
  outputTokens: number;
  /// Web 検索の実行回数。トークンとは別建ての課金なので記録する
  webSearchRequests: number;
  /// pause_turn で積み直した回数（0 なら1回のリクエストで完結した）
  resumedTurns: number;
  /// 上限まで再送しても pause_turn のままだった＝返答が途中で終わっている
  truncated: boolean;
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

/// 1ターン分のストリーム。client.messages.stream のうち、ここで使う分だけを写した形
/// （テストでスタブに差し替えられるようにインタフェースで切っている）。
export interface ChatStream {
  on(event: "text", handler: (delta: string) => void): unknown;
  finalMessage(): Promise<Pick<Anthropic.Message, "content" | "usage" | "stop_reason">>;
}

/// messages を渡してストリームを1本張る。pause_turn のたびに呼び直される。
export type ChatStreamStarter = (messages: Anthropic.Messages.MessageParam[]) => ChatStream;

export type ChatTurnsResult = Omit<ChatReplyResult, "model">;

/// サーバーツール（web_search / web_fetch）は Anthropic 側でループし、上限に達すると
/// stop_reason: "pause_turn" で止まる。そのままだと返答が途中で切れたまま保存されるので、
/// アシスタントのターンを messages に積んで再送し、続きを書かせる。
/// 本文・トークン・検索回数はターンをまたいで足し合わせる。
export async function runChatStreamTurns(
  start: ChatStreamStarter,
  messages: Anthropic.Messages.MessageParam[],
  onText: (fullText: string) => void
): Promise<ChatTurnsResult> {
  const turns = [...messages];
  const flusher = createTextFlusher(onText);
  let text = "";
  let inputTokens = 0;
  let outputTokens = 0;
  let webSearchRequests = 0;
  let resumedTurns = 0;
  let truncated = false;

  for (;;) {
    const stream = start(turns);
    stream.on("text", (delta) => {
      text += delta;
      flusher.push(text);
    });

    const final = await stream.finalMessage();
    inputTokens += final.usage.input_tokens;
    outputTokens += final.usage.output_tokens;
    webSearchRequests += final.usage.server_tool_use?.web_search_requests ?? 0;

    if (final.stop_reason !== "pause_turn") break;
    if (resumedTurns >= CHAT_PAUSE_TURN_MAX_RETRIES) {
      // これ以上は付き合わない。途中まででも返し、呼び出し側で分かるよう印を付ける
      truncated = true;
      break;
    }

    resumedTurns += 1;
    // 応答には server_tool_use / web_search_tool_result のブロックも混ざる。
    // 続きを書かせるにはそれらも含めてそのまま積み直す必要がある。
    turns.push({ role: "assistant", content: final.content as Anthropic.Messages.ContentBlockParam[] });
  }

  flusher.flush();
  return { text, inputTokens, outputTokens, webSearchRequests, resumedTurns, truncated };
}

/// 生成の進みに合わせて onText へ「そこまでの全文」を渡し、
/// 完了したら ChatReplyResult（保存・課金ログ用）を返す。
/// 途中で signal が中断されたら例外になるので、呼び出し側は保存しないこと。
export async function generateChatReplyStream(
  pages: ChatPage[],
  history: ChatMessage[],
  question: string,
  options: ChatReplyStreamOptions
): Promise<ChatReplyResult> {
  const system = buildChatSystemPrompt(pages);
  const result = await runChatStreamTurns(
    (messages) =>
      client.messages.stream(
        {
          model: config.writingChatModel,
          max_tokens: 2048,
          thinking: { type: "disabled" },
          system,
          tools: CHAT_TOOLS,
          messages,
        },
        { signal: options.signal }
      ),
    buildChatMessages(history, question),
    options.onText
  );

  const trimmed = result.text.trim();
  if (!trimmed) {
    throw new Error("Claude APIからテキスト応答が得られませんでした");
  }

  return { ...result, text: trimmed, model: config.writingChatModel };
}
