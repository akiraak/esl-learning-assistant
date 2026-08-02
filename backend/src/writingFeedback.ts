import { config } from "./config";
import { callStructured } from "./ocrTranslate";

// iOS側の WritingFeedback（Composition.swift）と同構造。フィールドを増減する場合は両方を合わせること。
const WRITING_FEEDBACK_SCHEMA = {
  type: "object",
  properties: {
    correctedText: {
      type: "string",
      description:
        "学習者が書いた英文を、伝えたかった意図に沿って自然で正しい英語に直した全文。" +
        "問題が無ければ元の英文をそのまま返す。",
    },
    explanation: {
      type: "string",
      description:
        "どこをなぜ直したかの解説。「解説言語」で指示された言語で書く。" +
        "文法・語彙・自然さの観点で、主要な修正点を箇条書き（Markdownの - 記法）で説明する。" +
        "修正が不要だった場合はその旨を書く。",
    },
  },
  required: ["correctedText", "explanation"],
  additionalProperties: false,
} as const;

export interface WritingFeedback {
  correctedText: string;
  explanation: string;
}

/// 過去の1ラウンド分（iOS の WritingRound と対応）。history として渡され、AI に文脈を与える。
export interface WritingFeedbackRound {
  englishText: string;
  japaneseText: string;
  correctedText: string;
  explanation: string;
}

export interface WritingFeedbackResult {
  feedback: WritingFeedback;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

export const WRITING_TEXT_MAX_LENGTH = 5000;
export const DEFAULT_EXPLANATION_LANGUAGE = "ja";
// 反復改善の履歴として AI に渡す過去ラウンドの上限（トークン肥大を防ぐため直近のみ）
export const WRITING_HISTORY_MAX_ROUNDS = 20;

/// バリデーション済みの添削リクエスト（本文は trim 済み、解説言語は既定値解決済み）
export interface WritingFeedbackRequest {
  englishText: string;
  japaneseText: string;
  explanationLanguage: string;
  history: WritingFeedbackRound[];
}

export type WritingFeedbackRequestValidation =
  | { ok: true; value: WritingFeedbackRequest }
  | { ok: false; error: string };

/// history を防御的に正規化する。配列でなければ [] を返し、各ラウンドの文字列フィールドを
/// クランプ、直近 WRITING_HISTORY_MAX_ROUNDS 件に丸める。無効な要素は落とす。
export function sanitizeWritingHistory(raw: unknown): WritingFeedbackRound[] {
  if (!Array.isArray(raw)) return [];
  const clamp = (value: unknown): string =>
    typeof value === "string" ? value.slice(0, WRITING_TEXT_MAX_LENGTH) : "";
  return raw
    .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
    .map((item) => ({
      englishText: clamp(item.englishText),
      japaneseText: clamp(item.japaneseText),
      correctedText: clamp(item.correctedText),
      explanation: clamp(item.explanation),
    }))
    .filter((round) => round.englishText.trim() !== "" && round.correctedText.trim() !== "")
    .slice(-WRITING_HISTORY_MAX_ROUNDS);
}

/// `/api/writing-feedback` の本文と `/admin/writing/:id/review` の共通バリデーション。
/// HTTP に依存しないよう、失敗は 400 の文言となるメッセージで返す。
export function validateWritingFeedbackRequest(body: unknown): WritingFeedbackRequestValidation {
  const { englishText, japaneseText, explanationLanguage, history } = (body ?? {}) as Record<string, unknown>;

  if (typeof englishText !== "string" || !englishText.trim()) {
    return { ok: false, error: "englishText is required" };
  }
  if (englishText.length > WRITING_TEXT_MAX_LENGTH) {
    return { ok: false, error: `englishText must be ${WRITING_TEXT_MAX_LENGTH} characters or fewer` };
  }
  if (typeof japaneseText !== "string" || !japaneseText.trim()) {
    return { ok: false, error: "japaneseText is required" };
  }
  if (japaneseText.length > WRITING_TEXT_MAX_LENGTH) {
    return { ok: false, error: `japaneseText must be ${WRITING_TEXT_MAX_LENGTH} characters or fewer` };
  }
  if (explanationLanguage !== undefined && typeof explanationLanguage !== "string") {
    return { ok: false, error: "explanationLanguage must be a string" };
  }

  return {
    ok: true,
    value: {
      englishText: englishText.trim(),
      japaneseText: japaneseText.trim(),
      explanationLanguage:
        typeof explanationLanguage === "string" && explanationLanguage.trim()
          ? explanationLanguage.trim()
          : DEFAULT_EXPLANATION_LANGUAGE,
      history: sanitizeWritingHistory(history),
    },
  };
}

export async function generateWritingFeedback(
  englishText: string,
  japaneseText: string,
  explanationLanguage: string,
  history: WritingFeedbackRound[] = []
): Promise<WritingFeedbackResult> {
  const hasHistory = history.length > 0;

  // これまでのラウンドを列挙し、改善の文脈を AI に与える
  const historyLines = hasHistory
    ? [
        `この作文は複数回にわたって書き直しながら改善しています。これまでのやり取りを踏まえて添削してください。`,
        `前回から改善した点があれば解説で前向きに触れ、まだ残る問題を指摘してください。`,
        ``,
        `【これまでのやり取り（古い順）】`,
        ...history.flatMap((round, index) => [
          `--- ラウンド${index + 1} ---`,
          `学習者の英文: ${round.englishText}`,
          `伝えたかった意図: ${round.japaneseText}`,
          `あなたの添削: ${round.correctedText}`,
          `解説: ${round.explanation}`,
          ``,
        ]),
      ]
    : [
        `学習者が書いた英文と、その学習者が「伝えたかった意図」を表す文章を渡します。`,
        `意図に沿って、自然で正しい英語に添削してください。`,
        ``,
      ];

  const prompt = [
    `あなたはESL学習者の英作文を添削する講師です。`,
    ...historyLines,
    hasHistory ? `【今回学習者が書いた英文】` : `【学習者が書いた英文】`,
    englishText,
    ``,
    hasHistory ? `【今回伝えたかった意図】` : `【伝えたかった意図（学習者の母語で書かれた訳または説明）】`,
    japaneseText,
    ``,
    `修正後の英文全文（correctedText）と、どこをなぜ直したかの解説（explanation）を返してください。`,
    `解説は言語コード "${explanationLanguage}" の言語で書いてください。`,
    `英文が既に自然で正しい場合は correctedText に元の英文をそのまま入れ、explanation でその旨を伝えてください。`,
  ].join("\n");

  const { json, inputTokens, outputTokens } = await callStructured<WritingFeedback>(
    config.writingFeedbackModel,
    WRITING_FEEDBACK_SCHEMA,
    [{ type: "text", text: prompt }]
  );

  return { feedback: json, model: config.writingFeedbackModel, inputTokens, outputTokens };
}
