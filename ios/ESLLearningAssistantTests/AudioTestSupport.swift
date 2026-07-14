import AVFoundation
import Foundation

/// 音声系テスト（AudioNormalizerTests / AudioImportTests）共有の WAV 合成・計測ヘルパ。
enum AudioTestSupport {
    /// 指定振幅の 440Hz sine 波 WAV（モノラル 44.1kHz / 16bit）を生成してその URL を返す。
    /// `spikeAmplitude` を与えると先頭付近に単発スパイクを重ねる（高クレストファクタ音源の模擬）。
    /// `name` を与えると一意な一時サブフォルダに素のファイル名で書く（ファイル名由来の title 検証用）。
    static func makeSineWAV(
        amplitude: Float,
        seconds: Double = 1.0,
        spikeAmplitude: Float? = nil,
        name: String? = nil
    ) throws -> URL {
        let sampleRate = 44100.0
        let url: URL
        if let name {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent(name)
        } else {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("audio-test-\(UUID().uuidString).wav")
        }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        )!
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            samples[i] = amplitude * sinf(2 * .pi * 440 * Float(i) / Float(sampleRate))
        }
        if let spikeAmplitude {
            samples[100] = spikeAmplitude
        }
        try file.write(from: buffer)
        return url
    }

    /// 音声ファイル全体の RMS(dBFS)・ピーク(dBFS)・長さ(秒) を測る。
    static func measure(url: URL) throws -> (rmsDB: Double, peakDB: Double, seconds: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768)!
        var sumSquares = 0.0
        var count = 0.0
        var peak: Float = 0
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            for channel in 0..<Int(format.channelCount) {
                let samples = buffer.floatChannelData![channel]
                for i in 0..<Int(buffer.frameLength) {
                    sumSquares += Double(samples[i] * samples[i])
                    peak = max(peak, abs(samples[i]))
                }
            }
            count += Double(buffer.frameLength) * Double(format.channelCount)
        }
        let rms = (sumSquares / count).squareRoot()
        return (20 * log10(rms), 20 * log10(Double(peak)), Double(file.length) / format.sampleRate)
    }
}
