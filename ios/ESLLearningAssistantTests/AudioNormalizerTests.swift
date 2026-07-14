import AVFoundation
import Foundation
import Testing
@testable import ESLLearningAssistant

/// `AudioNormalizer`（取り込み音声の音量ノーマライズ）を、テスト内で合成した WAV で検証する。
/// 出力は AAC（非可逆）なので、RMS/ピークの検証はやや緩いトレランスで行う。
struct AudioNormalizerTests {
    @Test func quietSineIsBoostedToTargetRMS() throws {
        // 振幅 0.05 の sine: RMS ≈ -29 dBFS / ピーク ≈ -26 dBFS → RMS 目標へ +13dB 増幅されるはず
        let input = try AudioTestSupport.makeSineWAV(amplitude: 0.05)
        defer { try? FileManager.default.removeItem(at: input) }

        let output = try #require(try AudioNormalizer.normalize(inputURL: input))
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(output.pathExtension == "aac")
        let measured = try AudioTestSupport.measure(url: output)
        // AAC 非可逆・エンコーダディレイの無音を含むため ±1.5dB 許容
        #expect(abs(measured.rmsDB - AudioNormalizer.targetRMSdB) < 1.5)
        #expect(measured.peakDB < AudioNormalizer.peakCeilingDB + 0.5)
    }

    @Test func loudSineIsAttenuatedByNegativeGain() throws {
        // 振幅 0.99 の sine: RMS ≈ -3.1 dBFS → 目標へ約 -13dB の負ゲインが掛かるはず
        let input = try AudioTestSupport.makeSineWAV(amplitude: 0.99)
        defer { try? FileManager.default.removeItem(at: input) }

        let output = try #require(try AudioNormalizer.normalize(inputURL: input))
        defer { try? FileManager.default.removeItem(at: output) }

        let measured = try AudioTestSupport.measure(url: output)
        #expect(abs(measured.rmsDB - AudioNormalizer.targetRMSdB) < 1.5)
        #expect(measured.peakDB < AudioNormalizer.peakCeilingDB + 0.5)
    }

    @Test func spikySourceIsCappedByPeakCeiling() throws {
        // 小音量 sine ＋ 単発スパイク（-0.9 dBFS）: RMS 目標までの増幅ではなく
        // ピーク上限で頭打ちになり、クリップしないこと
        let input = try AudioTestSupport.makeSineWAV(amplitude: 0.05, spikeAmplitude: 0.9)
        defer { try? FileManager.default.removeItem(at: input) }

        let output = try #require(try AudioNormalizer.normalize(inputURL: input))
        defer { try? FileManager.default.removeItem(at: output) }

        let measured = try AudioTestSupport.measure(url: output)
        #expect(measured.peakDB < AudioNormalizer.peakCeilingDB + 0.5)
        // RMS 目標には届かない（ピークキャップが効いている）
        #expect(measured.rmsDB < AudioNormalizer.targetRMSdB - 5)
    }

    @Test func veryQuietSourceIsLimitedByMaxGain() throws {
        // 振幅 0.001 の sine: RMS ≈ -63 dBFS。目標まで +47dB 必要だが最大増幅 +20dB で頭打ち
        let input = try AudioTestSupport.makeSineWAV(amplitude: 0.001)
        defer { try? FileManager.default.removeItem(at: input) }

        let output = try #require(try AudioNormalizer.normalize(inputURL: input))
        defer { try? FileManager.default.removeItem(at: output) }

        let measured = try AudioTestSupport.measure(url: output)
        let expectedRMS = -63.1 + AudioNormalizer.maxGainDB
        #expect(abs(measured.rmsDB - expectedRMS) < 2.0)
    }

    @Test func silentSourceIsSkipped() throws {
        let input = try AudioTestSupport.makeSineWAV(amplitude: 0)
        defer { try? FileManager.default.removeItem(at: input) }
        #expect(try AudioNormalizer.normalize(inputURL: input) == nil)
    }

    @Test func brokenDataThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("normalizer-test-broken-\(UUID().uuidString).wav")
        try Data((0..<1024).map { UInt8($0 % 251) }).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: Error.self) {
            try AudioNormalizer.normalize(inputURL: url)
        }
    }

    @Test func outputIsPlayableAACWithSimilarDuration() throws {
        let input = try AudioTestSupport.makeSineWAV(amplitude: 0.3, seconds: 2.0)
        defer { try? FileManager.default.removeItem(at: input) }

        let output = try #require(try AudioNormalizer.normalize(inputURL: input))
        defer { try? FileManager.default.removeItem(at: output) }

        let measured = try AudioTestSupport.measure(url: output)
        // AAC はエンコーダディレイ/パディングで数千フレーム伸びるため 0.2 秒許容
        #expect(abs(measured.seconds - 2.0) < 0.2)
    }

    @Test func gainFormulaPicksSmallestCap() {
        // RMS 目標が最小 → RMS ゲイン採用
        #expect(AudioNormalizer.gainDB(rmsDB: -29, peakDB: -26) == 13)
        // ピーク上限が最小 → ピークキャップ採用（負方向にも働く）
        #expect(AudioNormalizer.gainDB(rmsDB: -29, peakDB: 0) == -1)
        // 最大増幅が最小 → +20dB で頭打ち
        #expect(AudioNormalizer.gainDB(rmsDB: -63, peakDB: -60) == 20)
        // 大きすぎる音源 → 負ゲイン
        #expect(AudioNormalizer.gainDB(rmsDB: -3, peakDB: 0) == -13)
    }
}
