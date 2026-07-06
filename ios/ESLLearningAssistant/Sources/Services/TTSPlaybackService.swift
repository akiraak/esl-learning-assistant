import AVFoundation

/// 生成済みTTS音声（TTSAudioStoreのローカルファイル、またはサーバから取得したWAVデータ）を再生する。
/// 一時停止・シーク・±5秒スキップ・再生速度の変更に対応し、操作パネル（TTSPlayerBar）の状態源になる。
/// 1画面に複数の再生ボタンが並ぶため、どのファイルを再生中かを currentURL で公開する。
@MainActor
final class TTSPlaybackService: NSObject, ObservableObject {
    /// ロード中の音源ファイル。データ再生（play(data:)）のときは nil のまま
    @Published private(set) var currentURL: URL?
    /// 音源がロードされているか（一時停止中も true）。操作パネルの表示条件
    @Published private(set) var isActive = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// 再生速度。音源をまたいで維持する（学習者が聞き取りやすい速度を選び直さなくて済むように）
    @Published private(set) var rate: Float = 1.0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    func play(url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            start(player: player, url: url)
        } catch {
            // 再生失敗は無音のまま終了する（ファイル破損時は生成し直せば復旧する）
            stop()
        }
    }

    /// 再生はせず、音源をロードだけして操作パネル（TTSPlayerBar）を一時停止状態で表示する。
    /// 詳細画面を開いた時点では自動再生せず、ユーザーが再生ボタンを押せるようにするため。
    /// 既に同じURLがアクティブなら何もしない（再ロードで再生位置をリセットしない）。
    func prepare(url: URL) {
        if isActive && currentURL == url { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            start(player: player, url: url, autoPlay: false)
        } catch {
            stop()
        }
    }

    /// サーバから取得したWAVデータをメモリから直接再生する（PhotoDetailViewのOCR全文読み上げ用）
    func play(data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            start(player: player, url: nil)
        } catch {
            stop()
        }
    }

    private func start(player: AVAudioPlayer, url: URL?, autoPlay: Bool = true) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            return
        }
        player.delegate = self
        player.enableRate = true
        player.rate = rate
        self.player = player
        currentURL = url
        isActive = true
        duration = player.duration
        currentTime = 0
        if autoPlay {
            player.play()
            isPlaying = true
            startProgressTimer()
            updateScreenWakeLock()
        } else {
            player.prepareToPlay()
        }
    }

    func pause() {
        guard let player, isPlaying else { return }
        player.pause()
        isPlaying = false
        currentTime = player.currentTime
        stopProgressTimer()
        updateScreenWakeLock()
    }

    func resume() {
        guard let player, !isPlaying else { return }
        player.play()
        isPlaying = true
        startProgressTimer()
        updateScreenWakeLock()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), duration)
        currentTime = player.currentTime
    }

    func skip(by seconds: TimeInterval) {
        guard let player else { return }
        seek(to: player.currentTime + seconds)
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        player?.rate = newRate
    }

    func stop() {
        player?.stop()
        player = nil
        stopProgressTimer()
        currentURL = nil
        isActive = false
        isPlaying = false
        currentTime = 0
        duration = 0
        updateScreenWakeLock()
    }

    /// 再生中だけ自動ロック（スリープ）を止め、途中で音が切れないようにする
    private func updateScreenWakeLock() {
        ScreenWakeLock.setActive(isPlaying, owner: self)
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
        // Listスクロール中（trackingモード）でもシークバーが止まらないよう common モードで回す
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

extension TTSPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            stop()
        }
    }
}
