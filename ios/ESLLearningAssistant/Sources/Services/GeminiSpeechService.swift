import AVFoundation

/// バックエンド（`POST /api/tts`、Gemini TTS中継）から音声データを取得して再生する。
@MainActor
final class GeminiSpeechService: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isSpeaking = false

    private struct RequestBody: Encodable {
        let text: String
        let voice: String
        let model: String
    }

    private var player: AVAudioPlayer?

    func speak(_ text: String, voice: String, model: String) {
        guard !text.isEmpty else { return }
        stop()

        let baseURLString = UserDefaults.standard.string(forKey: AppSettingsKeys.backendBaseURL)
            ?? AppSettingsKeys.defaultBackendBaseURL
        guard let url = URL(string: baseURLString)?.appendingPathComponent("api/tts") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(RequestBody(text: text, voice: voice, model: model))

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback)
                try session.setActive(true)

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    return
                }
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                isSpeaking = true
                player.play()
            } catch {
                // 生成・再生に失敗した場合は無音のまま終了する
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
