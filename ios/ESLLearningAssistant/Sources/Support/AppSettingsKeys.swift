import Foundation

enum AppSettingsKeys {
    static let backendBaseURL = "backendBaseURL"
    static let targetLanguageCode = "targetLanguageCode"
    static let ttsEngine = "ttsEngine"
    static let ttsVoice = "ttsVoice"
    static let ttsModel = "ttsModel"

    /// ビルド時にInfo.plistへ埋め込まれた値（実機ビルドはrun-ios-device.shがMacのIPで上書きする）。
    /// 未設定・空ならローカル開発の既定値にフォールバックする。
    static var defaultBackendBaseURL: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
           !value.isEmpty {
            return value
        }
        return "http://localhost:8801"
    }
    static let defaultTargetLanguageCode = "ja"
    /// "local"（端末内蔵AVSpeechSynthesizer） or "gemini"（バックエンド経由Gemini TTS）
    static let defaultTTSEngine = "local"
    /// "chobi"（ちょビ/Leda） or "naruko"（なるこ/Aoede）
    static let defaultTTSVoice = "chobi"
    /// "flash"（gemini-2.5-flash-preview-tts、高速） or "pro"（gemini-2.5-pro-preview-tts、高音質）
    static let defaultTTSModel = "flash"
}
