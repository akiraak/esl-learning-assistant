import {
  extractAndTranslateDocument,
  type DocumentExtractRequestFields,
} from "./documentExtract";
import { insertDocumentLog } from "./db";
import { estimateCostUsd } from "./pricing";
import { logger } from "./logger";
import { createJobStore, type JobState } from "./jobStore";

// 文書抽出＋翻訳の実行結果（アプリへ返すレスポンスボディと同形）。
export interface DocumentExtractTranslateOutcome {
  extractedText: string;
  translatedText: string;
  translationLanguage: string;
}

/// 文書抽出＋翻訳の本体処理。extractAndTranslateDocument の実行と、成功/失敗の
/// document_requests への課金記録・ログ出力までを行う。同期エンドポイント
/// （POST /api/document-extract-translate）と非同期ジョブの両方から呼ぶ共通処理。
/// 失敗時は記録を残した上で throw する（呼び出し側が HTTP 500 / ジョブ failed にする）。
export async function runDocumentExtractTranslate(
  fields: DocumentExtractRequestFields,
  documentFilename: string
): Promise<DocumentExtractTranslateOutcome> {
  const { fileBuffer, mediaType, fileKind, targetLanguage, title } = fields;
  const startedAt = Date.now();
  try {
    const result = await extractAndTranslateDocument(fileBuffer, mediaType, targetLanguage);
    const latencyMs = Date.now() - startedAt;

    const extractCostUsd = result.extractModel
      ? estimateCostUsd(result.extractModel, result.extractInputTokens, result.extractOutputTokens)
      : 0;
    const translateCostUsd = estimateCostUsd(
      result.translateModel,
      result.translateInputTokens,
      result.translateOutputTokens
    );

    insertDocumentLog({
      documentFilename,
      title,
      mediaType,
      fileKind,
      targetLanguage,
      byteSize: fileBuffer.length,
      extractionMethod: result.extractionMethod,
      extractedText: result.extractedText,
      translatedText: result.translatedText,
      extractModel: result.extractModel,
      extractInputTokens: result.extractInputTokens,
      extractOutputTokens: result.extractOutputTokens,
      translateModel: result.translateModel,
      translateInputTokens: result.translateInputTokens,
      translateOutputTokens: result.translateOutputTokens,
      extractCostUsd,
      translateCostUsd,
      costUsd: extractCostUsd + translateCostUsd,
      status: "success",
      errorMessage: null,
      latencyMs,
    });

    logger.info(
      `document-extract-translate: success document=${documentFilename} latencyMs=${latencyMs} ` +
        `method=${result.extractionMethod} ` +
        `tokens=extract:${result.extractInputTokens}/${result.extractOutputTokens} ` +
        `translate:${result.translateInputTokens}/${result.translateOutputTokens} ` +
        `cost=$${(extractCostUsd + translateCostUsd).toFixed(4)}`
    );
    return {
      extractedText: result.extractedText,
      translatedText: result.translatedText,
      translationLanguage: targetLanguage,
    };
  } catch (error) {
    const latencyMs = Date.now() - startedAt;
    const errorMessage = error instanceof Error ? error.message : String(error);

    insertDocumentLog({
      documentFilename,
      title,
      mediaType,
      fileKind,
      targetLanguage,
      byteSize: fileBuffer.length,
      extractionMethod: null,
      extractedText: null,
      translatedText: null,
      extractModel: null,
      extractInputTokens: 0,
      extractOutputTokens: 0,
      translateModel: null,
      translateInputTokens: 0,
      translateOutputTokens: 0,
      extractCostUsd: 0,
      translateCostUsd: 0,
      costUsd: 0,
      status: "error",
      errorMessage,
      latencyMs,
    });

    logger.error(
      `document-extract-translate: failed document=${documentFilename} latencyMs=${latencyMs} error=${errorMessage}`
    );
    throw error;
  }
}

// --- 非同期ジョブストア -------------------------------------------------------
//
// Cloudflare の 100 秒タイムアウト（HTTP 524）対策として、文書抽出＋翻訳はジョブ受付→
// ポーリングの非同期 API でも提供する。ジョブは単一プロセスのメモリ上 Map で管理する
// （本番は単一コンテナ・ジョブは数分で完了するため永続化はしない。サーバー再起動で
// 消えたジョブは GET が 404 を返し、アプリ側が失敗として扱う）。
// 汎用ロジックは jobStore.ts（単体テスト対象）にあり、ここでは文書用に束ねるだけ。

export type DocumentJobState = JobState<DocumentExtractTranslateOutcome>;

// ジョブの保持期間（作成時刻起点）。アプリのポーリング上限（15 分）より十分長く取る。
export const DOCUMENT_JOB_TTL_MS = 30 * 60 * 1000;

const store = createJobStore<DocumentExtractTranslateOutcome>(DOCUMENT_JOB_TTL_MS);

/// ジョブを登録して即座に jobId を返す。run には runDocumentExtractTranslate を渡す想定。
export const createDocumentJob = store.create;
/// ジョブの現在状態を返す。未知の jobId・TTL 超過なら null（HTTP 404 相当）。
export const getDocumentJob = store.get;
