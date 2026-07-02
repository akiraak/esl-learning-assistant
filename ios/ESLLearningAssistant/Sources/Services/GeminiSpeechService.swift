import AVFoundation

/// バックエンド（`POST /api/tts`、Gemini TTS中継）から音声データを取得して再生する。
@MainActor
final class GeminiSpeechService: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isSpeaking = false
    /// 401（API Secret未設定・不一致）のユーザー向けメッセージ。表示側でalertに使う
    @Published var errorMessage: String?

    private struct RequestBody: Encodable {
        let text: String
        let voice: String
        let model: String
    }

    private var player: AVAudioPlayer?

    func speak(_ text: String, voice: String, model: String) {
        guard !text.isEmpty else { return }
        stop()

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback)
                try session.setActive(true)

                let data = try await BackendAPI.post(
                    path: "api/tts",
                    body: RequestBody(text: text, voice: voice, model: model)
                )
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                isSpeaking = true
                player.play()
            } catch BackendAPIError.unauthorized {
                errorMessage = BackendAPIError.unauthorized.localizedDescription
            } catch {
                // 401以外の生成・再生失敗は従来どおり無音のまま終了する
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isSpeaking = false
    }
}

extension GeminiSpeechService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
