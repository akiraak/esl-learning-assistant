import AVFoundation

/// 取り込み音声の音量ノーマライズ。録音環境で音量がまちまちな音源を、取り込み時点で
/// 聞き取りやすいレベルに揃える。再生側（AVAudioPlayer）は増幅できないため、
/// ファイル自体を正規化して保存する方式（docs/plans/audio-import-volume-normalization.md）。
///
/// - 2パス・チャンク処理（メモリ一定）: 1パス目で全体の RMS/ピークを分析し、
///   2パス目でゲインを掛けて書き出す。
/// - ゲインは RMS を目標値へ近づけつつ、ピーク上限・最大増幅でキャップして
///   リミッター無しでもクリップしないようにする。
/// - 出力は AAC（ADTS, `.aac`）。文字起こし対応形式で、非可逆で十分小さく、
///   AVAudioPlayer で再生できる。m4a/mp4（文字起こし非対応）も取り込み後は対応形式になる。
enum AudioNormalizer {
    enum NormalizeError: Error {
        /// PCM デコード用のチャネルデータが取れない（想定外フォーマット）
        case unsupportedFormat
    }

    /// 目標 RMS（dBFS）。授業録音の聞き取りやすさを優先した控えめなラウドネス。
    static let targetRMSdB: Double = -16
    /// ピーク上限（dBFS）。ゲイン適用後のピークがこれを超えないよう制限する。
    static let peakCeilingDB: Double = -1
    /// 最大増幅（dB）。極端に小さい音源での異常増幅（ノイズ持ち上げ）を抑止する。
    static let maxGainDB: Double = 20
    /// これ以下のピークは実質無音とみなし、正規化をスキップする（≈ -100 dBFS）
    private static let silencePeakThreshold: Float = 1e-5
    /// 1チャンクのフレーム数。32768 frames × float32 × ch 数ぶんのメモリで頭打ちになる。
    private static let chunkFrames: AVAudioFrameCount = 32768

    /// 音声ファイルを正規化し、一時ディレクトリに書き出した `.aac` の URL を返す。
    /// - Returns: 正規化済みファイルの URL。実質無音でスキップした場合は nil（元データをそのまま使う）。
    /// - Throws: デコード・エンコード不能時。呼び出し側は元データ保存にフォールバックする。
    static func normalize(inputURL: URL) throws -> URL? {
        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat

        let analysis = try analyze(file: inputFile, format: format)
        guard analysis.peak > silencePeakThreshold, analysis.rms > 0 else { return nil }

        let gain = Float(pow(10.0, gainDB(rmsDB: analysis.rmsDB, peakDB: analysis.peakDB) / 20.0))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("normalized-\(UUID().uuidString).aac")
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: encoderSettings(for: format),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        do {
            inputFile.framePosition = 0
            try forEachChunk(of: inputFile, format: format) { buffer, channelData in
                for channel in 0..<Int(format.channelCount) {
                    let samples = channelData[channel]
                    for i in 0..<Int(buffer.frameLength) {
                        // ピーク上限でキャップ済みなのでクリップしないはずだが、丸め誤差の保険に ±1 へ収める
                        samples[i] = max(-1, min(1, samples[i] * gain))
                    }
                }
                try outputFile.write(from: buffer)
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
        return outputURL
    }

    /// ゲイン（dB）を決める。RMS を目標へ近づけつつ、ピーク上限と最大増幅で制限する。
    /// 大きすぎる音源には負のゲインが掛かる（ピーク上限超えも同式で必ず収まる）。
    static func gainDB(rmsDB: Double, peakDB: Double) -> Double {
        min(targetRMSdB - rmsDB, peakCeilingDB - peakDB, maxGainDB)
    }

    private struct Analysis {
        let rms: Double
        let peak: Float
        var rmsDB: Double { 20 * log10(rms) }
        var peakDB: Double { 20 * log10(Double(peak)) }
    }

    /// 1パス目: 全チャンネル・全フレームの RMS とピーク（絶対値）を集計する。
    private static func analyze(file: AVAudioFile, format: AVAudioFormat) throws -> Analysis {
        var sumSquares = 0.0
        var sampleCount = 0.0
        var peak: Float = 0

        file.framePosition = 0
        try forEachChunk(of: file, format: format) { buffer, channelData in
            for channel in 0..<Int(format.channelCount) {
                let samples = channelData[channel]
                for i in 0..<Int(buffer.frameLength) {
                    let sample = samples[i]
                    sumSquares += Double(sample * sample)
                    peak = max(peak, abs(sample))
                }
            }
            sampleCount += Double(buffer.frameLength) * Double(format.channelCount)
        }
        return Analysis(rms: sampleCount > 0 ? (sumSquares / sampleCount).squareRoot() : 0, peak: peak)
    }

    /// ファイルをチャンク単位に読み、非インターリーブ float32 のチャネルデータごと処理へ渡す。
    private static func forEachChunk(
        of file: AVAudioFile,
        format: AVAudioFormat,
        _ body: (AVAudioPCMBuffer, UnsafePointer<UnsafeMutablePointer<Float>>) throws -> Void
    ) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw NormalizeError.unsupportedFormat
        }
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            guard let channelData = buffer.floatChannelData else {
                throw NormalizeError.unsupportedFormat
            }
            try body(buffer, channelData)
        }
    }

    /// AAC エンコード設定。サンプルレート・チャンネル数は元を維持、ビットレートは 128kbps 目安。
    /// AAC-LC の上限（約 6bit/sample/ch）を超えるとエンコーダ生成に失敗するため、
    /// 低サンプルレート・モノラル音源では安全な値まで下げる。
    private static func encoderSettings(for format: AVAudioFormat) -> [String: Any] {
        let channels = Int(format.channelCount)
        let perChannelBitRate = min(64_000, 6 * Int(format.sampleRate))
        return [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: min(128_000, perChannelBitRate * channels),
        ]
    }
}
