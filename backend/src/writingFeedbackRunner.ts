import { config } from "./config";
import { insertWritingFeedbackLog } from "./db";
import { logger } from "./logger";
import { estimateCostUsd } from "./pricing";
import {
  generateWritingFeedback,
  type WritingFeedback,
  type WritingFeedbackRequest,
} from "./writingFeedback";

export interface WritingFeedbackRunResult {
  feedback: WritingFeedback;
  model: string;
}

/// 添削の生成と課金ログ記録をまとめた共通処理。`/api/writing-feedback`（iOS 等の外部クライアント）と
/// `/admin/writing/:id/review`（Web 画面）の両方がここを通る。
/// **ログ記録はこの関数の中だけで行う**（呼び出し側でも記録すると利用料金が二重計上される）。
/// 失敗時もログを1件残したうえで例外を再送出する。
export async function runWritingFeedback(
  request: WritingFeedbackRequest,
  source: string
): Promise<WritingFeedbackRunResult> {
  const startedAt = Date.now();
  logger.info(
    `writing-feedback: start source=${source} englishLen=${request.englishText.length} ` +
      `japaneseLen=${request.japaneseText.length} historyRounds=${request.history.length} ` +
      `explanationLanguage=${request.explanationLanguage} model=${config.writingFeedbackModel}`
  );

  try {
    const result = await generateWritingFeedback(
      request.englishText,
      request.japaneseText,
      request.explanationLanguage,
      request.history
    );
    const latencyMs = Date.now() - startedAt;

    insertWritingFeedbackLog({
      englishText: request.englishText,
      japaneseText: request.japaneseText,
      explanationLanguage: request.explanationLanguage,
      feedbackJson: JSON.stringify(result.feedback),
      model: result.model,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      costUsd: estimateCostUsd(result.model, result.inputTokens, result.outputTokens),
      status: "success",
      errorMessage: null,
      latencyMs,
    });

    logger.info(`writing-feedback: success source=${source} latencyMs=${latencyMs}`);
    return { feedback: result.feedback, model: result.model };
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);

    insertWritingFeedbackLog({
      englishText: request.englishText,
      japaneseText: request.japaneseText,
      explanationLanguage: request.explanationLanguage,
      feedbackJson: null,
      model: config.writingFeedbackModel,
      inputTokens: 0,
      outputTokens: 0,
      costUsd: 0,
      status: "error",
      errorMessage,
      latencyMs,
    });

    logger.error(`writing-feedback: failed source=${source} latencyMs=${latencyMs} error=${errorMessage}`);
    throw error;
  }
}
