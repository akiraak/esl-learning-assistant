import XCTest
@testable import ESLLearningAssistant

/// TTS設定の起動時マイグレーション（AppSettingsKeys.migrateLegacyTTSEngineIfNeeded）の検証。
/// 旧モデルキー "flash" / "pro"（Gemini 2.5世代）は選択肢から廃止したため、
/// 残っていると Settings の Picker がどの選択肢にも一致しなくなる。"flash31" へ読み替える。
final class AppSettingsKeysMigrationTests: XCTestCase {
    private let suiteName = "AppSettingsKeysMigrationTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLegacyFlashIsRemappedToFlash31() {
        defaults.set("flash", forKey: AppSettingsKeys.ttsModel)
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.ttsModel), "flash31")
    }

    func testLegacyProIsRemappedToFlash31() {
        defaults.set("pro", forKey: AppSettingsKeys.ttsModel)
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.ttsModel), "flash31")
    }

    func testLocalAndFlash31AreKept() {
        defaults.set("local", forKey: AppSettingsKeys.ttsModel)
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.ttsModel), "local")

        defaults.set("flash31", forKey: AppSettingsKeys.ttsModel)
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.ttsModel), "flash31")
    }

    func testUnsetStaysUnset() {
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: AppSettingsKeys.ttsModel))
    }

    /// 廃止済み "ttsEngine"（local/gemini）からの二段移行: gemini だった場合も最終的に flash31 になる
    func testLegacyEngineGeminiMigratesToFlash31() {
        defaults.set("gemini", forKey: "ttsEngine")
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.ttsModel), "flash31")
        XCTAssertNil(defaults.string(forKey: "ttsEngine"))
    }

    func testLegacyEngineLocalMigratesToLocal() {
        defaults.set("local", forKey: "ttsEngine")
        AppSettingsKeys.migrateLegacyTTSEngineIfNeeded(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppSettingsKeys.ttsModel), "local")
        XCTAssertNil(defaults.string(forKey: "ttsEngine"))
    }
}
