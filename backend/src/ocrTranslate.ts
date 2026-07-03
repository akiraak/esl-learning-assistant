import Anthropic from "@anthropic-ai/sdk";
import { config } from "./config";

const client = new Anthropic({ apiKey: config.anthropicApiKey });

const OCR_TEXT_PROPERTY = {
  type: "string",
  description:
    "画像から文字起こしした英語の原文。Markdown形式で、見出しは#、箇条書きは-、" +
    "強調は**太字**/*斜体*など、原文のレイアウトが分かる記法を使うこと。",
} as const;

const OCR_SCHEMA = {
  type: "object",
  properties: { ocrText: OCR_TEXT_PROPERTY },
  required: ["ocrText"],
  additionalProperties: false,
} as const;

const TRANSLATE_SCHEMA = {
  type: "object",
  properties: {
    translatedText: {
      type: "string",
      description:
        "入力文を目的言語に翻訳した文章。入力文と同じMarkdown構造（見出し・箇条書き・強調）を保つこと。",
    },
  },
  required: ["translatedText"],
  additionalProperties: false,
} as const;

const COMBINED_SCHEMA = {
  type: "object",
  properties: {
    ocrText: OCR_TEXT_PROPERTY,
    translatedText: {
      type: "string",
      description:
        "ocrTextを目的言語に翻訳した文章。ocrTextと同じMarkdown構造（見出し・箇条書き・強調）を保つこと。",
    },
  },
  required: ["ocrText", "translatedText"],
  additionalProperties: false,
} as const;

export interface StructuredCallResult<T> {
  json: T;
  inputTokens: number;
  outputTokens: number;
}

// claude-haiku-4-5はoutput_config.effortパラメータ非対応
// （"This model does not support the effort parameter."で400エラーになる）ため、
// haiku系モデルではeffortを付けずに呼び出す。
export async function callStructured<T>(
  model: string,
  schema: Record<string, unknown>,
  content: Anthropic.Messages.ContentBlockParam[],
  maxTokens = 4096
): Promise<StructuredCallResult<T>> {
  const response = await client.messages.create({
    model,
    max_tokens: maxTokens,
    thinking: { type: "disabled" },
    output_config: {
      ...(model.includes("haiku") ? {} : { effort: "low" }),
      format: { type: "json_schema", schema },
    },
    messages: [{ role: "user", content }],
  });

  const textBlock = response.content.find((block) => block.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    throw new Error("Claude APIからテキスト応答が得られませんでした");
  }

  return {
    json: JSON.parse(textBlock.text) as T,
    inputTokens: response.usage.input_tokens,
    outputTokens: response.usage.output_tokens,
  };
}

function imageContent(
  imageBase64: string,
  mediaType: "image/jpeg" | "image/png"
): Anthropic.Messages.ImageBlockParam {
  return { type: "image", source: { type: "base64", media_type: mediaType, data: imageBase64 } };
}

async function ocrImage(imageBase64: string, mediaType: "image/jpeg" | "image/png") {
  const { json, inputTokens, outputTokens } = await callStructured<{ ocrText: string }>(
    config.ocrModel,
    OCR_SCHEMA,
    [
      imageContent(imageBase64, mediaType),
      {
        type: "text",
        text:
          `この教科書ページの画像から英語の本文をMarkdown形式で文字起こししてください（ocrText）。` +
          `見出し・箇条書き・強調（太字/斜体）など、原文のレイアウトが分かるようにMarkdown記法を使ってください。`,
      },
    ]
  );
  return { text: json.ocrText, inputTokens, outputTokens };
}

async function translateText(ocrText: string, targetLanguageCode: string) {
  const { json, inputTokens, outputTokens } = await callStructured<{ translatedText: string }>(
    config.translateModel,
    TRANSLATE_SCHEMA,
    [
      {
        type: "text",
        text:
          `次のMarkdown形式の文章を言語コード "${targetLanguageCode}" にMarkdown形式のまま翻訳してください` +
          `（translatedText）。見出し・箇条書き・強調（太字/斜体）など、元のMarkdown構造を保ってください。\n\n` +
          `---\n${ocrText}`,
      },
    ]
  );
  return { text: json.translatedText, inputTokens, outputTokens };
}

async function combinedOcrAndTranslate(
  imageBase64: string,
  mediaType: "image/jpeg" | "image/png",
  targetLanguageCode: string
) {
  const { json, inputTokens, outputTokens } = await callStructured<{
    ocrText: string;
    translatedText: string;
  }>(config.ocrModel, COMBINED_SCHEMA, [
    imageContent(imageBase64, mediaType),
    {
      type: "text",
      text:
        `この教科書ページの画像から英語の本文をMarkdown形式で文字起こしし（ocrText）、` +
        `その文章を言語コード "${targetLanguageCode}" にMarkdown形式のまま翻訳してください（translatedText）。` +
        `見出し・箇条書き・強調（太字/斜体）など、原文のレイアウトが分かるようにMarkdown記法を使ってください。`,
    },
  ]);
  return { ocrText: json.ocrText, translatedText: json.translatedText, inputTokens, outputTokens };
}

export interface OcrTranslateResult {
  ocrText: string;
  translatedText: string;
  ocrModel: string;
  ocrInputTokens: number;
  ocrOutputTokens: number;
  translateModel: string;
  translateInputTokens: number;
  translateOutputTokens: number;
}

export async function ocrAndTranslate(
  imageBase64: string,
  mediaType: "image/jpeg" | "image/png",
  targetLanguageCode: string
): Promise<OcrTranslateResult> {
  // OCRモデルと翻訳モデルが同じ場合、2回に分けても同じモデルに2回課金されるだけで
  // 翻訳ステップの入力にOCR結果を再度渡す分のトークンが余分にかかるだけなので、
  // 元の設計どおり1回の呼び出しにまとめる。モデルが異なる場合のみ2回に分ける。
  if (config.ocrModel === config.translateModel) {
    const combined = await combinedOcrAndTranslate(imageBase64, mediaType, targetLanguageCode);
    return {
      ocrText: combined.ocrText,
      translatedText: combined.translatedText,
      ocrModel: config.ocrModel,
      ocrInputTokens: combined.inputTokens,
      ocrOutputTokens: combined.outputTokens,
      translateModel: config.translateModel,
      translateInputTokens: 0,
      translateOutputTokens: 0,
    };
  }

  const ocrResult = await ocrImage(imageBase64, mediaType);
  const translateResult = await translateText(ocrResult.text, targetLanguageCode);

  return {
    ocrText: ocrResult.text,
    translatedText: translateResult.text,
    ocrModel: config.ocrModel,
    ocrInputTokens: ocrResult.inputTokens,
    ocrOutputTokens: ocrResult.outputTokens,
    translateModel: config.translateModel,
    translateInputTokens: translateResult.inputTokens,
    translateOutputTokens: translateResult.outputTokens,
  };
}
