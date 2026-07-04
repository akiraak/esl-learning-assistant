import Foundation

/// クイズ開始前の音声一括ダウンロード（docs/plans/quiz-audio-predownload.md Phase 2）。
/// 確定済み問題の audioText を `POST /api/tts` から取得して TTSAudioStore に保存する。
/// サーバは問題生成時にプリ合成済みのため基本はキャッシュ返却で高速。未合成分は
/// サーバがその場で合成して返す（自己修復）。
/// 1件あたり数十〜240KB 程度のため、進捗はファイル単位の完了数で報告する。
enum QuizAudioDownloader {
    private struct RequestBody: Encodable {
        let text: String
        let model: String
    }

    /// tts.ts のチャンク合成やサーバのプリ合成（並列2）と同程度の控えめな並列度
    private static let concurrency = 2

    /// texts を並列ダウンロードし、最終的に失敗したテキストの集合を返す。
    /// 各件は失敗時に1回リトライする。保存済みのテキストは即成功として数える。
    /// Task キャンセル時は残りが失敗扱いになる（呼び出し側はキャンセルなら結果を捨てる想定）。
    static func download(
        texts: [String],
        model: String = AppSettingsKeys.quizTTSModel,
        onProgress: @escaping @Sendable @MainActor (_ completed: Int, _ total: Int) -> Void
    ) async -> Set<String> {
        let total = texts.count
        guard total > 0 else { return [] }

        var failed: Set<String> = []
        var completed = 0
        await withTaskGroup(of: (text: String, success: Bool).self) { group in
            var nextIndex = 0
            func addNextIfAny() {
                guard nextIndex < texts.count else { return }
                let text = texts[nextIndex]
                nextIndex += 1
                group.addTask { (text, await fetchAndSave(text, model: model)) }
            }
            for _ in 0..<min(concurrency, texts.count) { addNextIfAny() }
            for await result in group {
                completed += 1
                if !result.success { failed.insert(result.text) }
                await onProgress(completed, total)
                addNextIfAny()
            }
        }
        return failed
    }

    private static func fetchAndSave(_ text: String, model: String) async -> Bool {
        // プリダウンロード済み・過去セッションで取得済みならネットワークに出ない
        if TTSAudioStore.localURL(text: text, model: model) != nil { return true }
        for attempt in 0..<2 {
            if Task.isCancelled { return false }
            do {
                let data = try await BackendAPI.post(
                    path: "api/tts",
                    body: RequestBody(text: text, model: model)
                )
                try TTSAudioStore.save(data: data, text: text, model: model)
                return true
            } catch {
                // 1回だけリトライ（詳細は BackendAPI がログ済み）
                if attempt == 0 { continue }
            }
        }
        return false
    }
}
