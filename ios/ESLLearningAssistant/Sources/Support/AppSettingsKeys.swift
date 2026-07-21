import Foundation

enum AppSettingsKeys {
    static let backendBaseURL = "backendBaseURL"
    static let apiSecret = "apiSecret"
    static let targetLanguageCode = "targetLanguageCode"
    static let ttsModel = "ttsModel"
    /// 音声取り込み時の音量ノーマライズ ON/OFF（既定 ON）。取り込み確認シートの Toggle で
    /// 切り替え、前回の選択を次回の初期値として引き継ぐ。
    static let audioImportNormalizeEnabled = "audioImportNormalizeEnabled"

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
    /// "flash31"（gemini-3.1-flash-tts-preview。サーバTTSはこれに一本化）
    static let defaultTTSModel = "local"
    /// サーバTTS（/api/tts）は "local" を受け付けないため、送信時はこのモデルに読み替える
    static let fallbackServerTTSModel = "flash31"
    /// クイズ音声のモデル。サーバがプリ合成に使う QUIZ_TTS_MODEL（backend/src/ttsStore.ts）と
    /// 一致させること。キャッシュキーが sha256("model|text") のため、ずれるとプリ合成が無駄になる。
    static let quizTTSModel = "flash31"

    /// 廃止した "ttsEngine"（local/gemini）設定を ttsModel へ一度だけ移行する。
    /// あわせて、廃止した "ttsVoice"（音声キャラ選択。サーバ側のランダム選択に移行）も掃除する。
    /// 旧モデルキー "flash" / "pro"（Gemini 2.5 世代）は "flash31" へ読み替える
    /// （選択肢からも廃止済み。残すと Picker のどの選択肢にも一致しなくなる）。
    static func migrateLegacyTTSEngineIfNeeded(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "ttsVoice")
        if let engine = defaults.string(forKey: "ttsEngine") {
            if engine == "local" {
                defaults.set("local", forKey: ttsModel)
            } else if defaults.string(forKey: ttsModel) == nil {
                defaults.set("flash31", forKey: ttsModel)
            }
            defaults.removeObject(forKey: "ttsEngine")
        }
        if let model = defaults.string(forKey: ttsModel), model == "flash" || model == "pro" {
            defaults.set("flash31", forKey: ttsModel)
        }
    }
}
