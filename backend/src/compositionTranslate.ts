import { createHash } from "node:crypto";
import { WRITING_TRANSLATE_CONTEXT_CHARS, WRITING_TRANSLATE_MAX_LENGTH } from "./composition";
import { config } from "./config";
import { callStructured } from "./ocrTranslate";

// 執筆画面（/admin/writing/:id）で英文を選択したときに出す和訳。
// docs/plans/writing-selection-translate.md: 選択は一文〜数語と短く、それだけでは
// 代名詞・時制・固有名詞の指す先が定まらないので、前後の文脈を添えて「選択部分だけ訳す」よう頼む。
// ocrTranslate の translateText() は「渡した文章を全部訳す」形で文脈を分けられないため、
// 共通ヘルパー callStructured() を専用プロンプトで直接呼ぶ（モデルは同じ config.translateModel）。

// 上限値は画面（compositionView.ts）とも共有するので、db にも API にも依存しない
// composition.ts に置いてある。
export { WRITING_TRANSLATE_CONTEXT_CHARS, WRITING_TRANSLATE_MAX_LENGTH };

const SELECTION_TRANSLATE_SCHEMA = {
  type: "object",
  properties: {
    translatedText: {
      type: "string",
      description:
        "選択部分だけの訳文。前後の文脈の訳を含めない。訳文以外の説明・注釈・引用符を付けない。",
    },
  },
  required: ["translatedText"],
  additionalProperties: false,
} as const;

/// 選択文字列を通信・キャッシュキーに使える形へ整える（純関数）。
/// 前後の空白だけ落とし、内部の改行・連続空白はそのまま残す（段落選択の形を壊さない）。
export function normalizeSelection(raw: string): string {
  return raw.trim();
}

/// 本文と選択範囲から前後の文脈を切り出す（純関数）。それぞれ最大 200 文字。
/// 語の途中で切れても構わない（訳出対象ではなく、文脈として渡すだけ）。
export function selectionContext(
  body: string,
  start: number,
  end: number
): { before: string; after: string } {
  const from = Math.max(0, Math.min(start, body.length));
  const to = Math.max(from, Math.min(end, body.length));
  return {
    before: body.slice(Math.max(0, from - WRITING_TRANSLATE_CONTEXT_CHARS), from),
    after: body.slice(to, to + WRITING_TRANSLATE_CONTEXT_CHARS),
  };
}

/// クライアントから来た文脈をサーバ側でも上限まで切り詰める（純関数）。
/// before は末尾側、after は先頭側を残す（選択に近いほうが文脈として効く）。
export function clampContext(before: string, after: string): { before: string; after: string } {
  return {
    before: before.slice(-WRITING_TRANSLATE_CONTEXT_CHARS),
    after: after.slice(0, WRITING_TRANSLATE_CONTEXT_CHARS),
  };
}

/// キャッシュキー。文脈が変われば訳も変わり得るので、言語・文脈も込みでハッシュする。
export function selectionHash(
  text: string,
  targetLanguage: string,
  contextBefore: string,
  contextAfter: string
): string {
  // 区切りは本文に現れない NUL。空白で繋ぐと「文脈の末尾」と「選択の先頭」の境目が消え、
  // 別物が同じキーになりうる。
  return createHash("sha256")
    .update([targetLanguage, contextBefore, text, contextAfter].join("\u0000"))
    .digest("hex");
}

/// モデルへ渡す本文を組み立てる（純関数）。文脈が両方とも空なら文脈なしの頼み方に切り替える。
export function buildTranslatePrompt(
  text: string,
  targetLanguage: string,
  contextBefore: string,
  contextAfter: string
): string {
  if (!contextBefore && !contextAfter) {
    return (
      `次の英文を言語コード "${targetLanguage}" に翻訳してください（translatedText）。` +
      `訳文だけを返し、説明や引用符を付けないでください。\n\n---\n${text}`
    );
  }
  return (
    `次の文章のうち、<selection> と </selection> で囲んだ部分だけを言語コード "${targetLanguage}" に` +
    `翻訳してください（translatedText）。前後の文はあくまで文脈で、訳文には含めないでください。` +
    `代名詞・時制・固有名詞が指す先は文脈から判断してください。` +
    `訳文だけを返し、説明や引用符を付けないでください。\n\n` +
    `---\n${contextBefore}<selection>${text}</selection>${contextAfter}`
  );
}

/// 翻訳本体。文脈付きプロンプトで callStructured() を呼び、モデル名・トークン数をそのまま返す。
export async function translateSelection(input: {
  text: string;
  targetLanguage: string;
  contextBefore: string;
  contextAfter: string;
}): Promise<{ text: string; model: string; inputTokens: number; outputTokens: number }> {
  const model = config.translateModel;
  const { json, inputTokens, outputTokens } = await callStructured<{ translatedText: string }>(
    model,
    SELECTION_TRANSLATE_SCHEMA,
    [
      {
        type: "text",
        text: buildTranslatePrompt(
          input.text,
          input.targetLanguage,
          input.contextBefore,
          input.contextAfter
        ),
      },
    ],
    2048
  );
  return { text: json.translatedText, model, inputTokens, outputTokens };
}
