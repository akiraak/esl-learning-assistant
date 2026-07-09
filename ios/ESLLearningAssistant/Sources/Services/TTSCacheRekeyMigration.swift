import Foundation
import SwiftData
import os

/// `MarkdownPlainText` のブロック境界修正（v1）に伴う TTS キャッシュのリキー移行。
///
/// 変換結果は TTS キャッシュキー sha256("model|text") そのものなので、修正で出力が変わる
/// テキスト（複数ブロックを含む Photo OCR / Docs 抽出英文）は既存の全文読み上げ音声が
/// 「未生成」扱いになり、そのままでは再合成（課金）が走る。そこで既存音声を端末ローカル
/// （`TTSAudioStore`）とサーバ（`POST /api/tts/rekey` → tts_audio）の両方で旧キー→新キーへ
/// 付け替え、再合成なしで引き継ぐ。Markdown 原文は端末の SwiftData にしかない
/// （サーバは変換後テキストしか持たない）ため、端末主導で行う。
///
/// 移行が全端末に行き渡ったら、本ファイルと `MarkdownPlainText.legacyPlainText` を削除する。
enum TTSCacheRekeyMigration {
    /// 完了フラグ（UserDefaults）。サーバ側の付け替えがすべて成功したときだけ立てる。
    /// 失敗（オフライン等）時は次回起動で再試行する（ローカル・サーバとも付け替えは冪等）。
    static let completedDefaultsKey = "ttsPlainTextRekeyV1"

    /// 全文読み上げ（TTSButton）が使いうるサーバTTSモデル。ユーザーが設定を切り替えながら
    /// 生成した過去分も引き継げるよう、現在の設定値ではなく両方を対象にする。
    private static let serverModels = ["flash", "pro"]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ESLLearningAssistant",
        category: "TTSCacheRekeyMigration"
    )

    struct Target: Equatable {
        let oldText: String
        let newText: String
    }

    private struct RekeyRequestBody: Encodable {
        let oldHash: String
        let newText: String
        let model: String
    }

    /// Markdown 原文の一覧から、変換修正でキャッシュキーが変わるものだけを抽出する。
    /// 単一段落など出力が変わらないものはキー不変なので対象外。重複原文は1件にまとめる。
    static func targets(markdownSources: [String]) -> [Target] {
        var seenOldTexts = Set<String>()
        var result: [Target] = []
        for source in markdownSources {
            let oldText = MarkdownPlainText.legacyPlainText(source)
            let newText = MarkdownPlainText.plainText(source)
            guard oldText != newText, !oldText.isEmpty, seenOldTexts.insert(oldText).inserted else { continue }
            result.append(Target(oldText: oldText, newText: newText))
        }
        return result
    }

    /// 起動時に1回だけ実行する。ユーザー操作とは独立に走るため、失敗しても機能は壊れない
    /// （未移行分は「未生成」表示に戻り、ボタン押下で再合成される、が課金されるので極力移行で引き継ぐ）。
    @MainActor
    static func runIfNeeded(modelContext: ModelContext) async {
        guard !UserDefaults.standard.bool(forKey: completedDefaultsKey) else { return }

        let sources = fetchMarkdownSources(modelContext)
        let targets = targets(markdownSources: sources)
        guard !targets.isEmpty else {
            UserDefaults.standard.set(true, forKey: completedDefaultsKey)
            logger.info("no rekey targets (\(sources.count) sources); marked done")
            return
        }

        logger.info("start: \(targets.count) texts x \(serverModels.count) models")
        var serverFailures = 0
        for target in targets {
            for model in serverModels {
                // ローカルはオフラインでも成立するので常に先に付け替える
                TTSAudioStore.rekeyLocalFile(oldText: target.oldText, newText: target.newText, model: model)
                do {
                    _ = try await BackendAPI.post(
                        path: "api/tts/rekey",
                        body: RekeyRequestBody(
                            oldHash: TTSAudioStore.key(text: target.oldText, model: model),
                            newText: target.newText,
                            model: model
                        )
                    )
                } catch {
                    serverFailures += 1
                    logger.error("server rekey failed (model=\(model, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        if serverFailures == 0 {
            UserDefaults.standard.set(true, forKey: completedDefaultsKey)
            logger.info("done: rekeyed \(targets.count) texts")
        } else {
            logger.warning("incomplete: \(serverFailures) server calls failed; will retry next launch")
        }
    }

    /// TTS 全文読み上げの入力になっている Markdown 原文（Photo OCR / Docs 抽出英文）を全件集める
    @MainActor
    private static func fetchMarkdownSources(_ modelContext: ModelContext) -> [String] {
        let photos = (try? modelContext.fetch(FetchDescriptor<Photo>())) ?? []
        let documents = (try? modelContext.fetch(FetchDescriptor<Document>())) ?? []
        return photos.compactMap(\.ocrText) + documents.compactMap(\.extractedText)
    }
}
