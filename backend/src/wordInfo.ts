import { config } from "./config";
import { callStructured } from "./ocrTranslate";

// iOS側の WordAIInfo（Word.swift）と同構造。フィールドを増減する場合は両方を合わせること。
// 省略可能な項目は structured output で確実に埋まるよう nullable + required にしている。
const WORD_INFO_SCHEMA = {
  type: "object",
  properties: {
    // NOTE: structured output APIはarrayのminItems/maxItemsに非対応（400エラー）のため
    // 件数制約はdescriptionで指示する
    senses: {
      type: "array",
      description:
        "語義1〜5件。context（教科書本文）がある場合は、そこで使われている語義を必ず先頭にする。" +
        "同綴異義（語源・意味が無関係な別見出し語）がある場合も senses は1つの配列にまとめ、" +
        "各要素の homographGroup で見出しを区別する。同じ homographGroup の語義は配列内で隣接させる。",
      items: {
        type: "object",
        properties: {
          meaning: { type: "string", description: "母語での意味（短く）" },
          englishDefinition: {
            type: "string",
            description:
              "英語での定義・言い換え。英英辞書スタイルで、ESL学習者向けに平易な語彙を使う。",
          },
          partOfSpeech: { type: "string", description: "品詞（母語表記。例:「動詞」）" },
          note: { type: ["string", "null"], description: "ニュアンス・使い分け。特に無ければnull" },
          homographGroup: {
            type: "integer",
            description:
              "同綴異義の見出しグループ番号（0始まりの連番）。語源・意味が無関係な同綴異義" +
              "（例: bank=銀行/川岸、fall=落ちる/秋、spring=春/ばね/泉）だけを別番号にする。" +
              "関連する多義（例: run=走る/経営する）や、品詞転換しただけで意味が同じ語" +
              "（例: rain=雨/雨が降る、water=水/水をやる）は同じ番号に保つ。" +
              "判定基準は『1枚の絵で両方の意味を教えられるか。教えられない＝別グループ』。" +
              "過剰に分割しないこと。context に対応する語義（senses 先頭）は必ずグループ0にする。",
          },
        },
        required: ["meaning", "englishDefinition", "partOfSpeech", "note", "homographGroup"],
        additionalProperties: false,
      },
    },
    pronunciation: {
      type: "object",
      properties: {
        ipa: { type: "string", description: "IPA発音記号（例: /ˈæp.əl/）" },
        syllables: {
          type: ["string", "null"],
          description: "音節区切りとアクセント位置。強勢音節を大文字にする（例: AP-ple）。単音節ならnull",
        },
      },
      required: ["ipa", "syllables"],
      additionalProperties: false,
    },
    inflections: {
      type: "array",
      description: "語形変化。該当するもののみ最大8件（無ければ空配列）。",
      items: {
        type: "object",
        properties: {
          form: {
            type: "string",
            description:
              "変化の種類を英語の文法用語で。例: \"third-person singular\", \"past tense\", \"past participle\", \"present participle\", \"plural\", \"comparative\", \"superlative\"",
          },
          text: { type: "string", description: "変化形（例: \"ran\"）" },
        },
        required: ["form", "text"],
        additionalProperties: false,
      },
    },
    examples: {
      type: "array",
      description: "例文2〜3件。contextがある場合はその文脈に合う場面設定にする。",
      items: {
        type: "object",
        properties: {
          english: { type: "string", description: "英語の例文" },
          translation: { type: "string", description: "母語訳" },
        },
        required: ["english", "translation"],
        additionalProperties: false,
      },
    },
    collocations: {
      type: "array",
      description: "よく使う組み合わせ0〜3件（例: \"make a decision\"）",
      items: { type: "string" },
    },
    synonyms: {
      type: "array",
      description: "類義語0〜3件",
      items: { type: "string" },
    },
    antonyms: {
      type: "array",
      description: "反意語0〜3件",
      items: { type: "string" },
    },
    usageNote: {
      type: ["string", "null"],
      description: "使用上の注意（可算/不可算、自動詞/他動詞、前置詞の組み合わせ等）。特に無ければnull",
    },
    cefrLevel: {
      type: ["string", "null"],
      description: "CEFR難易度目安。A1/A2/B1/B2/C1/C2のいずれか。不明ならnull",
    },
    etymology: {
      type: ["string", "null"],
      description: "語源・記憶のヒント（覚え方）。有用なものが無ければnull",
    },
    register: {
      type: ["string", "null"],
      description: "使用域（フォーマル/カジュアル/スラング等。母語表記）。中立ならnull",
    },
    commonMistakes: {
      type: ["string", "null"],
      description: "学習者がよくする間違い・混同しやすい点。特に無ければnull",
    },
  },
  required: [
    "senses",
    "pronunciation",
    "inflections",
    "examples",
    "collocations",
    "synonyms",
    "antonyms",
    "usageNote",
    "cefrLevel",
    "etymology",
    "register",
    "commonMistakes",
  ],
  additionalProperties: false,
} as const;

export interface WordSense {
  meaning: string;
  englishDefinition: string;
  partOfSpeech: string;
  note: string | null;
  /** 同綴異義の見出しグループ番号（0始まり）。語源・意味が無関係な語だけ別番号 */
  homographGroup: number;
}

export interface WordInfo {
  senses: WordSense[];
  pronunciation: { ipa: string; syllables: string | null };
  inflections: { form: string; text: string }[];
  examples: { english: string; translation: string }[];
  collocations: string[];
  synonyms: string[];
  antonyms: string[];
  usageNote: string | null;
  cefrLevel: string | null;
  etymology: string | null;
  register: string | null;
  commonMistakes: string | null;
}

export interface WordInfoResult {
  wordInfo: WordInfo;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

export async function generateWordInfo(
  word: string,
  targetLanguage: string,
  context?: string,
  userTranslation?: string
): Promise<WordInfoResult> {
  const promptParts = [
    `英単語 "${word}" について、ESL学習者向けの単語情報を生成してください。`,
    `「母語」と指示されている項目は言語コード "${targetLanguage}" の言語で書いてください。`,
  ];
  if (userTranslation) {
    promptParts.push(
      `学習者はこの単語を「${userTranslation}」という意味で登録しました。語義の選定・並び順のヒントにしてください。`
    );
  }
  if (context) {
    promptParts.push(
      `この単語は次の教科書本文に登場しました。本文で使われている語義をsensesの先頭にし、` +
        `例文もこの文脈に合う場面設定にしてください。\n\n---\n${context}`
    );
  }

  const { json, inputTokens, outputTokens } = await callStructured<WordInfo>(
    config.wordInfoModel,
    WORD_INFO_SCHEMA,
    [{ type: "text", text: promptParts.join("\n") }]
  );

  return { wordInfo: json, model: config.wordInfoModel, inputTokens, outputTokens };
}
