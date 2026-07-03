import Foundation

/// バックエンド（`POST /api/tts`、Gemini TTS中継）から音声データを取得し、
/// TTSPlaybackService に渡して再生する（再生制御・状態はすべて playback 側が持つ）。
@MainActor
final class GeminiSpeechService: ObservableObject {
    @Published private(set) var isLoading = false
    /// 401（API Secret未設定・不一致）のユーザー向けメッセージ。表示側でalertに使う
    @Published var errorMessage: String?

    private struct RequestBody: Encodable {
        let text: String
        let voice: String
        let model: String
    }

    func speak(_ text: String, voice: String, model: String, playback: TTSPlaybackService) {
        guard !text.isEmpty, !isLoading else { return }
        playback.stop()

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let data = try await BackendAPI.post(
                    path: "api/tts",
                    body: RequestBody(text: text, voice: voice, model: model)
                )
                playback.play(data: data)
            } catch BackendAPIError.unauthorized {
                errorMessage = BackendAPIError.unauthorized.localizedDescription
            } catch {
                // 401以外の生成・再生失敗は従来どおり無音のまま終了する
            }
        }
    }
}
