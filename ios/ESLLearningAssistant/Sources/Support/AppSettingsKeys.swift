import Foundation

enum AppSettingsKeys {
    static let backendBaseURL = "backendBaseURL"
    static let apiSecret = "apiSecret"
    static let targetLanguageCode = "targetLanguageCode"
    static let ttsModel = "ttsModel"

    /// ビルド時にInfo.plistへ埋め込まれた値（実機ビルドはrun-ios-device.shがMacのIPで上書きする）。
    /// 未設定・空なら本番URLにフォールバックする（ローカル開発時はSettings画面で切り替える）。
    static var defaultBackendBaseURL: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           !value.isEmpty {
            return value
        }
        return "https://esl.chobi.me"
    }

    /// /api/* 認証用のX-API-Secretヘッダ値。ビルド時にInfo.plistへ埋め込める
    /// （run-ios-device.shがbackend/.envのAPI_SECRETを注入する）。既定は空＝未設定で、
    /// その場合はSettings画面での入力が必要。secret値はコードにハードコードしない。
    static var defaultAPISecret: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BackendAPISecret") as? String,
           !value.isEmpty {
            return value
        }
        return ""
    }
    static let defaultTargetLanguageCode = "ja"
    /// "local"（端末内蔵AVSpeechSynthesizer）,
    /// "flash"（gemini-2.5-flash-preview-tts）, "pro"（gemini-2.5-pro-preview-tts）
    static let defaultTTSModel = "local"
    /// サーバTTS（/api/tts）は "local" を受け付けないため、送信時はこのモデルに読み替える
    static let fallbackServerTTSModel = "flash"
    /// クイズ音声のモデル。サーバがプリ合成に使う QUIZ_TTS_MODEL（backend/src/ttsStore.ts）と
    /// 一致させること。キャッシュキーが sha256("model|text") のため、ずれるとプリ合成が無駄になる。
    static let quizTTSModel = "flash"

    /// 廃止した "ttsEngine"（local/gemini）設定を ttsModel（local/flash/pro）へ一度だけ移行する。
    /// あわせて、廃止した "ttsVoice"（音声キャラ選択。サーバ側のランダム選択に移行）も掃除する。
    static func migrateLegacyTTSEngineIfNeeded(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "ttsVoice")
        guard let engine = defaults.string(forKey: "ttsEngine") else { return }
        if engine == "local" {
            defaults.set("local", forKey: ttsModel)
        } else if defaults.string(forKey: ttsModel) == nil {
            defaults.set("flash", forKey: ttsModel)
        }
        defaults.removeObject(forKey: "ttsEngine")
    }
}
