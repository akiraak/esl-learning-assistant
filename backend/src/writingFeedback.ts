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
