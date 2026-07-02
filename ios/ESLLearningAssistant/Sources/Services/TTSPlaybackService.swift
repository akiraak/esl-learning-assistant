import AVFoundation

/// 端末ローカルに保存済みのTTS音声ファイル（TTSAudioStore）を再生する。
/// 1画面に複数の再生ボタンが並ぶため、どのファイルを再生中かを playingURL で公開する。
@MainActor
final class TTSPlaybackService: NSObject, ObservableObject {
    @Published private(set) var playingURL: URL?

    private var player: AVAudioPlayer?

    func play(url: URL) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            self.player = player
            playingURL = url
            player.play()
        } catch {
            // 再生失敗は無音のまま終了する（ファイル破損時は生成し直せば復旧する）
            playingURL = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
    }
}

extension TTSPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            playingURL = nil
        }
    }
}
