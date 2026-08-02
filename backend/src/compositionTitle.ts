import { config } from "./config";
import { callStructured } from "./ocrTranslate";

// 執筆画面（/admin/writing/:id）の「本文から生成」で使う、作文の記事タイトル生成。
// docs/plans/composition-title.md: タイトルは任意で、空欄なら一覧・読書ページは
// これまでどおり本文の先頭から見出しを作る。

/// 保存・入力の上限。手入力にも生成結果にも同じ上限を当てる。
export const COMPOSITION_TITLE_MAX_LENGTH = 120;

/// プロンプトに載せる本文の上限（相談チャットと同じ。超える分は末尾を切る）
export const TITLE_SOURCE_MAX_LENGTH = 5000;

const TITLE_SCHEMA = {
  type: "object",
  properties: {
    title: {
      type: "string",
      description:
        "本文の内容を表す英語のタイトル。5〜8語程度の名詞句で、末尾にピリオドは付けない。" +
        "引用符で囲まない。本文に無い出来事を足さない。",
    },
  },
  required: ["title"],
  additionalProperties: false,
} as const;

/// 生成結果・手入力を保存できる形に整える（純関数）。
/// - 改行は空白へ（1行の見出しとして扱うため）
/// - モデルが付けがちな囲みの引用符（" ' 「」）と末尾のピリオドを落とす
/// - 連続する空白を1つにまとめ、上限で切る
export function sanitizeCompositionTitle(raw: string): string {
  let value = raw.replace(/[\r\n\t]+/g, " ").replace(/\s+/g, " ").trim();
  // 前後が対になっている囲みだけを剥がす（英文中の引用符は残す）
  const quotePairs: [string, string][] = [
    ['"', '"'],
    ["'", "'"],
    ["“", "”"],
    ["「", "」"],
    ["『", "』"],
  ];
  for (const [open, close] of quotePairs) {
    if (value.length >= 2 && value.startsWith(open) && value.endsWith(close)) {
      value = value.slice(open.length, value.length - close.length).trim();
      break;
    }
  }
  value = value.replace(/[.。]+$/, "").trim();
  return value.slice(0, COMPOSITION_TITLE_MAX_LENGTH);
}

export interface CompositionTitleResult {
  title: string;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

/// 「適度な短さ」は語数（5〜8語）で指示し、長さの担保は sanitize 側の上限で行う。
export function buildTitlePrompt(compositionText: string): string {
  return [
    `次はESL学習者が書いている英作文です。この文章に付ける記事タイトルを1つ作ってください。`,
    ``,
    `【本文】`,
    compositionText.trim().slice(0, TITLE_SOURCE_MAX_LENGTH),
    ``,
    `条件:`,
    `- 英語で書く（本文が英作文のため）`,
    `- 5〜8語程度の短い名詞句にする。文にしない`,
    `- 末尾にピリオドを付けない。引用符で囲まない`,
    `- 本文に書かれていない出来事・主張を足さない`,
    `- 書きかけで内容が乏しいときは、いま書かれている範囲だけからタイトルを付ける`,
  ].join("\n");
}

export async function generateCompositionTitle(compositionText: string): Promise<CompositionTitleResult> {
  const { json, inputTokens, outputTokens } = await callStructured<{ title: string }>(
    config.writingTitleModel,
    TITLE_SCHEMA,
    [{ type: "text", text: buildTitlePrompt(compositionText) }],
    256
  );

  const title = sanitizeCompositionTitle(json.title ?? "");
  if (!title) {
    throw new Error("Claude APIからタイトルが得られませんでした");
  }

  return { title, model: config.writingTitleModel, inputTokens, outputTokens };
}
