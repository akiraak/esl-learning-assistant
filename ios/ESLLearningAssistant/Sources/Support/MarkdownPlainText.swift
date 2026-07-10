import Foundation

/// Markdown 文字列から記号（`#` / `**` 等）を除いたプレーンテキストを取り出す。
/// TTS 読み上げに Markdown 記号を発音させないための共通ヘルパー（Photo / Document 詳細で共用）。
///
/// 注意: 出力テキストは TTS キャッシュ（`TTSAudioStore` / サーバ `tts_audio`）のキーそのものになる。
/// 変換ロジックを変えると既存キャッシュが無効化され再合成（課金）が走るため、安易に変更しない。
/// 変える場合は旧キー→新キーのリキー移行をセットで行うこと（v1 の例: git 履歴の `TTSCacheRekeyMigration`）。
enum MarkdownPlainText {
    static func plainText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let attributed = try? AttributedString(markdown: value, options: options) else {
            return value
        }
        // AttributedString(markdown:) はブロック境界の改行を落とすため、
        // ブロック（見出し・段落・リスト項目）ごとに文字列を集めて空行で連結し直す。
        // ブロックの同一性は presentationIntent の identity チェーンで判定する
        // （末端 components だけではリスト項目同士が同一視されて連結される）。
        var blocks: [String] = []
        var currentIdentity: [Int]? = nil
        var currentBlock = ""
        for run in attributed.runs {
            let identity = run.presentationIntent?.components.map(\.identity)
            if identity != currentIdentity, !currentBlock.isEmpty {
                blocks.append(currentBlock)
                currentBlock = ""
            }
            currentIdentity = identity
            currentBlock += String(attributed.characters[run.range])
        }
        if !currentBlock.isEmpty { blocks.append(currentBlock) }
        return blocks.joined(separator: "\n\n")
    }
}
