import Foundation

enum AppSettingsKeys {
    static let backendBaseURL = "backendBaseURL"
    static let targetLanguageCode = "targetLanguageCode"

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
}
