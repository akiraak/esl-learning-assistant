import Foundation

enum AppSettingsKeys {
    static let backendBaseURL = "backendBaseURL"
    static let apiSecret = "apiSecret"
    static let targetLanguageCode = "targetLanguageCode"
    static let ttsEngine = "ttsEngine"
    static let ttsVoice = "ttsVoice"
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
    /// "local"（端末内蔵AVSpeechSynthesizer） or "gemini"（バックエンド経由Gemini TTS）
    static let defaultTTSEngine = "local"
    /// "chobi"（ちょビ/Leda） or "naruko"（なるこ/Aoede）
    static let defaultTTSVoice = "chobi"
    /// "flash"（gemini-2.5-flash-preview-tts、高速） or "pro"（gemini-2.5-pro-preview-tts、高音質）
    static let defaultTTSModel = "flash"
}
