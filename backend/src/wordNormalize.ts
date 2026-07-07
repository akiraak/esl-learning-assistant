import { config } from "./config";
import { callStructured } from "./ocrTranslate";

// 入力語を辞書見出し語（lemma）へ正規化した結果。iOS 側 WordNormalization（Sources/Models）と同構造。
// フィールドを増減する場合は両方を合わせること。
//
// status で確認UIの出し分けを決める（詳細は docs/plans/word-input-normalization.md）:
//   canonical    既に見出し語 → lemma は入力と同じ / 確認UIを出さず即登録
//   inflected    語形変化（過去形/複数形/比較級等）→ lemma は原形 / 確認UIを出す
//   misspelled   綴り間違い → lemma は正しい綴り / 確認UIを出す
//   proper_noun  固有名詞（人名等）→ 訂正しない（lemma は入力と同じ）
//   phrase       複数語の連語 → lemma は入力と同じ
//   unknown      判定不能・英語でない → lemma は入力と同じ
export const WORD_NORMALIZE_STATUSES = [
  "canonical",
  "inflected",
  "misspelled",
  "proper_noun",
  "phrase",
  "unknown",
] as const;

export type WordNormalizeStatus = (typeof WORD_NORMALIZE_STATUSES)[number];

const WORD_NORMALIZE_SCHEMA = {
  type: "object",
  properties: {
    status: {
      type: "string",
      enum: [...WORD_NORMALIZE_STATUSES],
      description:
        "入力語の分類。" +
        "canonical=既に辞書見出し語（原形・正しい綴り）。" +
        "inflected=語形変化（過去形・過去分詞・三単現・複数形・比較級・最上級・-ing形など）。" +
        "misspelled=綴り間違い。" +
        "proper_noun=固有名詞（人名・地名・商品名など。訂正しない）。" +
        "phrase=空白を含む複数語の連語。" +
        "unknown=英単語として判定できない・英語でない。",
    },
    lemma: {
      type: "string",
      description:
        "登録すべき見出し語。inflected なら原形、misspelled なら正しい綴りにする。" +
        "canonical/proper_noun/phrase/unknown では入力語をそのまま（トリムのみ）返す。小文字化はしない。",
    },
    reason: {
      type: "string",
      description:
        "なぜその lemma に直したかを『母語』（指定された言語コードの言語）で1文で説明する。" +
        "例（inflected）:「『ran』は動詞『run』の過去形です」。" +
        "canonical/proper_noun/phrase/unknown の場合は空文字列 \"\" を返す（確認UIを出さないため）。",
    },
  },
  required: ["status", "lemma", "reason"],
  additionalProperties: false,
} as const;

export interface WordNormalization {
  status: WordNormalizeStatus;
  lemma: string;
  reason: string;
}

export interface WordNormalizeResult {
  normalization: WordNormalization;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

export async function normalizeWord(
  word: string,
  targetLanguage: string
): Promise<WordNormalizeResult> {
  const prompt = [
    `英語学習アプリの語彙リスト登録の前処理として、入力された語 "${word}" を辞書見出し語（lemma）へ正規化してください。`,
    `目的は、過去形・複数形などの語形変化を原形に、綴り間違いを正しい綴りに直して、正しい見出し語で登録することです。`,
    `reason は言語コード "${targetLanguage}" の言語（母語）で書いてください。`,
    `固有名詞・連語・英語でない入力は訂正せず、そのまま返してください。`,
  ].join("\n");

  const { json, inputTokens, outputTokens } = await callStructured<WordNormalization>(
    config.wordNormalizeModel,
    WORD_NORMALIZE_SCHEMA,
    [{ type: "text", text: prompt }]
  );

  return {
    normalization: json,
    model: config.wordNormalizeModel,
    inputTokens,
    outputTokens,
  };
}
