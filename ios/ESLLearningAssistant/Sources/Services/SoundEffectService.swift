import AVFoundation
import UIKit

/// クイズの正誤フィードバック効果音とハプティックを鳴らす。
/// 正解=気持ちいい上昇チャイム（correct.caf）、不正解=それとない低音ブリップ（wrong.caf）。
///
/// TTS 再生（TTSPlaybackService の .playback セッション）とは独立した短時間再生。
/// 消音スイッチを尊重する `.ambient` セッションを使い、TTS など他の音を止めない。
/// プレイヤーは事前ロードして解答直後の遅延を抑える。
@MainActor
final class SoundEffectService {
    private var correctPlayer: AVAudioPlayer?
    private var wrongPlayer: AVAudioPlayer?
    private let notificationFeedback = UINotificationFeedbackGenerator()

    init() {
        correctPlayer = Self.makePlayer(named: "correct")
        wrongPlayer = Self.makePlayer(named: "wrong")
        correctPlayer?.prepareToPlay()
        wrongPlayer?.prepareToPlay()
    }

    /// 正誤に応じて効果音とハプティックを鳴らす。
    func playAnswerFeedback(isCorrect: Bool) {
        configureSessionIfNeeded()
        let player = isCorrect ? correctPlayer : wrongPlayer
        player?.currentTime = 0
        player?.play()
        notificationFeedback.notificationOccurred(isCorrect ? .success : .warning)
    }

    /// 効果音は他再生を止めず、消音スイッチに従う `.ambient`。
    /// TTS が直前に .playback をアクティブにしている場合でも、短い効果音のために
    /// mixWithOthers で共存させる。失敗しても無音で継続する（学習の妨げにしない）。
    private func configureSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private static func makePlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else {
            return nil
        }
        return try? AVAudioPlayer(contentsOf: url)
    }
}
