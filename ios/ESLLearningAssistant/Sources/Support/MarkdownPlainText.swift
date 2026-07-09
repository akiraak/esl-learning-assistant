import Foundation

/// Markdown 文字列から記号（`#` / `**` 等）を除いたプレーンテキストを取り出す。
/// TTS 読み上げに Markdown 記号を発音させないための共通ヘルパー（Photo / Document 詳細で共用）。
///
/// 注意: 出力テキストは TTS キャッシュ（`TTSAudioStore` / サーバ `tts_audio`）のキーそのものになる。
/// 変換ロジックを変えると既存キャッシュが無効化され再合成（課金）が走るため、安易に変更しない。
enum MarkdownPlainText {
    static func plainText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let attributed = try? AttributedString(markdown: value, options: options) else {
            return value
        }
        return String(attributed.characters)
    }
}
