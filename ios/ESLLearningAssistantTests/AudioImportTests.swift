import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import ESLLearningAssistant

/// `AudioFileImporter.importFiles`（取り込み → `AudioClip` 化）を検証する。
/// 正規化 ON なら `.aac` で保存され音量が目標へ揃うこと、OFF なら元データがそのまま
/// 保存されること、正規化に失敗しても元データへフォールバックすることを見る。
/// `AudioStorage` に書かれた実ファイルは作成された `audioFileName` を辿って個別に掃除する。
@MainActor
struct AudioImportTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self,
            AudioClip.self, Document.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func cleanUpStorage(_ clips: [AudioClip]) {
        for clip in clips {
            AudioStorage.delete(fileName: clip.audioFileName)
        }
    }

    @Test func importWithNormalizeSavesNormalizedAAC() async throws {
        let context = try makeContext()
        // 小音量 WAV（RMS ≈ -29 dBFS）。取り込み後は AAC 化され目標 RMS 近傍まで増幅されるはず
        let input = try AudioTestSupport.makeSineWAV(amplitude: 0.05, name: "lecture.wav")
        defer { try? FileManager.default.removeItem(at: input) }

        let count = await AudioFileImporter.importFiles(
            [input], into: nil, context: context, normalize: true
        )

        let clips = try context.fetch(FetchDescriptor<AudioClip>())
        defer { cleanUpStorage(clips) }

        #expect(count == 1)
        let clip = try #require(clips.first)
        #expect(clip.title == "lecture") // title は元ファイル名由来のまま
        #expect(clip.audioFileName.hasSuffix(".aac"))
        let storedURL = AudioStorage.url(fileName: clip.audioFileName)
        let attributes = try FileManager.default.attributesOfItem(atPath: storedURL.path)
        #expect(clip.byteSize == (attributes[.size] as? Int)) // byteSize は保存した実データのサイズ
        let measured = try AudioTestSupport.measure(url: storedURL)
        #expect(abs(measured.rmsDB - AudioNormalizer.targetRMSdB) < 1.5)
    }

    @Test func importWithoutNormalizeKeepsOriginalData() async throws {
        let context = try makeContext()
        let input = try AudioTestSupport.makeSineWAV(amplitude: 0.05, name: "raw.wav")
        defer { try? FileManager.default.removeItem(at: input) }
        let originalData = try Data(contentsOf: input)

        let count = await AudioFileImporter.importFiles(
            [input], into: nil, context: context, normalize: false
        )

        let clips = try context.fetch(FetchDescriptor<AudioClip>())
        defer { cleanUpStorage(clips) }

        #expect(count == 1)
        let clip = try #require(clips.first)
        #expect(clip.audioFileName.hasSuffix(".wav")) // 拡張子は元のまま
        let stored = try Data(contentsOf: AudioStorage.url(fileName: clip.audioFileName))
        #expect(stored == originalData) // 中身もバイト一致
    }

    @Test func importFallsBackToOriginalWhenNormalizationFails() async throws {
        let context = try makeContext()
        // AVAudioFile で開けない壊れた「.wav」→ 正規化は失敗するが元データで取り込まれる
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let input = dir.appendingPathComponent("broken.wav")
        let originalData = Data((0..<2048).map { UInt8($0 % 251) })
        try originalData.write(to: input)
        defer { try? FileManager.default.removeItem(at: dir) }

        let count = await AudioFileImporter.importFiles(
            [input], into: nil, context: context, normalize: true
        )

        let clips = try context.fetch(FetchDescriptor<AudioClip>())
        defer { cleanUpStorage(clips) }

        #expect(count == 1)
        let clip = try #require(clips.first)
        #expect(clip.audioFileName.hasSuffix(".wav"))
        let stored = try Data(contentsOf: AudioStorage.url(fileName: clip.audioFileName))
        #expect(stored == originalData)
    }

    @Test func importLinksClipToLesson() async throws {
        let context = try makeContext()
        let schoolClass = Class(name: "English")
        let lesson = Lesson(schoolClass: schoolClass, title: "Lesson 1")
        context.insert(schoolClass)
        context.insert(lesson)
        try context.save()

        let input = try AudioTestSupport.makeSineWAV(amplitude: 0.3, name: "class-audio.wav")
        defer { try? FileManager.default.removeItem(at: input) }

        let count = await AudioFileImporter.importFiles(
            [input], into: lesson, context: context, normalize: true
        )

        let clips = try context.fetch(FetchDescriptor<AudioClip>())
        defer { cleanUpStorage(clips) }

        #expect(count == 1)
        let clip = try #require(clips.first)
        #expect(clip.lessons.map(\.id) == [lesson.id])
        #expect(lesson.audioClips.map(\.id) == [clip.id]) // inverse も張られる
    }
}
