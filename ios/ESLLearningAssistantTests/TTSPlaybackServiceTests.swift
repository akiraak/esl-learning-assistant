import AVFoundation
import XCTest
@testable import ESLLearningAssistant

@MainActor
final class TTSPlaybackServiceTests: XCTestCase {
    private var wavURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TTSPlaybackServiceTests-\(UUID().uuidString).wav")
        try Self.makeSilentWAV(duration: 2.0).write(to: wavURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: wavURL)
        try super.tearDownWithError()
    }

    func testPlayPauseResumeStop() throws {
        let service = TTSPlaybackService()
        XCTAssertFalse(service.isActive)

        service.play(url: wavURL)
        XCTAssertTrue(service.isActive)
        XCTAssertTrue(service.isPlaying)
        XCTAssertEqual(service.currentURL, wavURL)
        XCTAssertEqual(service.duration, 2.0, accuracy: 0.1)

        service.pause()
        XCTAssertTrue(service.isActive)
        XCTAssertFalse(service.isPlaying)

        service.resume()
        XCTAssertTrue(service.isPlaying)

        service.stop()
        XCTAssertFalse(service.isActive)
        XCTAssertFalse(service.isPlaying)
        XCTAssertNil(service.currentURL)
        XCTAssertEqual(service.currentTime, 0)
        XCTAssertEqual(service.duration, 0)
    }

    func testSeekAndSkipClampToAudioRange() throws {
        let service = TTSPlaybackService()
        service.play(url: wavURL)
        service.pause()

        service.seek(to: 1.0)
        XCTAssertEqual(service.currentTime, 1.0, accuracy: 0.1)

        // 音源の長さを超えるシークは末尾へ、負方向スキップは先頭へクランプされる
        service.seek(to: 100)
        XCTAssertLessThanOrEqual(service.currentTime, service.duration + 0.01)

        service.skip(by: -100)
        XCTAssertEqual(service.currentTime, 0, accuracy: 0.01)

        service.stop()
    }

    func testRatePersistsAcrossPlaybacks() throws {
        let service = TTSPlaybackService()
        service.setRate(0.75)
        XCTAssertEqual(service.rate, 0.75)

        // 新しい音源を再生しても選んだ速度が維持される
        service.play(url: wavURL)
        XCTAssertEqual(service.rate, 0.75)
        service.stop()
        XCTAssertEqual(service.rate, 0.75)
    }

    func testPlayDataActivatesWithoutURL() throws {
        let service = TTSPlaybackService()
        service.play(data: Self.makeSilentWAV(duration: 1.0))
        XCTAssertTrue(service.isActive)
        XCTAssertTrue(service.isPlaying)
        XCTAssertNil(service.currentURL)
        XCTAssertEqual(service.duration, 1.0, accuracy: 0.1)
        service.stop()
    }

    func testPrepareLoadsWithoutAutoPlaying() throws {
        let service = TTSPlaybackService()

        // ロードのみ：アクティブだが再生はしていない
        service.prepare(url: wavURL)
        XCTAssertTrue(service.isActive)
        XCTAssertFalse(service.isPlaying)
        XCTAssertEqual(service.currentURL, wavURL)

        // 再生ボタン相当（resume）で再生が始まる
        service.resume()
        XCTAssertTrue(service.isPlaying)

        service.stop()
        XCTAssertFalse(service.isActive)
    }

    /// 16bitモノラルPCMの無音WAVを生成する（バックエンドが返すWAVと同形式）
    private static func makeSilentWAV(duration: Double, sampleRate: Int = 8000) -> Data {
        let sampleCount = Int(duration * Double(sampleRate))
        let dataSize = sampleCount * 2
        var wav = Data()
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.append(uint32: UInt32(36 + dataSize))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.append(uint32: 16)
        wav.append(uint16: 1) // PCM
        wav.append(uint16: 1) // mono
        wav.append(uint32: UInt32(sampleRate))
        wav.append(uint32: UInt32(sampleRate * 2)) // byte rate
        wav.append(uint16: 2) // block align
        wav.append(uint16: 16) // bits per sample
        wav.append(contentsOf: Array("data".utf8))
        wav.append(uint32: UInt32(dataSize))
        wav.append(Data(count: dataSize))
        return wav
    }
}

private extension Data {
    mutating func append(uint32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(uint16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
