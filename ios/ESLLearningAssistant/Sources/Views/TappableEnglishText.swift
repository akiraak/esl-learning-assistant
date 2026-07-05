import MarkdownUI
import SwiftData
import SwiftUI

// MARK: - タップハンドラの環境値

/// 英文中の単語がタップされたときに呼ばれるアクション。SwiftUI の `OpenURLAction` に倣い、
/// 環境値としてビュー階層へ配布する。これにより深い階層（`WordAIInfoSections` など）へ
/// `onWordTap` をバケツリレーせずに済む。`WordRegistrationModifier` が実体を注入する。
// クロージャは SwiftUI のビュー（MainActor）からのみ生成・呼び出しされるため unchecked Sendable でよい。
// 環境キーの defaultValue が Sendable を要求するための宣言。
struct WordTapAction: @unchecked Sendable {
    private let action: (String) -> Void

    init(_ action: @escaping (String) -> Void) {
        self.action = action
    }

    func callAsFunction(_ word: String) {
        action(word)
    }
}

private struct WordTapActionKey: EnvironmentKey {
    // 既定は何もしない（登録モディファイアが無い画面ではタップしても無反応）
    static let defaultValue = WordTapAction { _ in }
}

extension EnvironmentValues {
    var wordTapAction: WordTapAction {
        get { self[WordTapActionKey.self] }
        set { self[WordTapActionKey.self] = newValue }
    }
}

// MARK: - プレーン英文（Text）のタップ対応

/// 英文を単語ごとにタップ可能にする `Text`。MarkdownUI を使わないプレーンな英文（例文・
/// 英英定義・コロケーションなど）向け。各単語に `eslword://add?w=<word>` のリンクを張り、
/// `openURL` を横取りして環境の `wordTapAction` を呼ぶ。リンク色は本文と同じ `.primary` に
/// 上書きし、折り返しは SwiftUI の `Text` に任せる。
struct TappableEnglishText: View {
    let text: String
    /// 単語（リンク）の文字色。標準の青リンク色を避け、本文と同じ見た目にするため明示指定する。
    /// セカンダリ表示の欄（英英定義など）では `.secondary` を渡して地の文と揃える。
    var color: Color = .primary
    @Environment(\.wordTapAction) private var wordTapAction

    var body: some View {
        Text(attributed)
            .environment(\.openURL, OpenURLAction { url in
                guard let word = EnglishWordLink.word(from: url) else { return .discarded }
                wordTapAction(word)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for token in EnglishWordLink.tokenize(text) {
            if token.isWord,
               let core = EnglishWordLink.core(of: token.text),
               let url = EnglishWordLink.linkURL(for: core) {
                var run = AttributedString(token.text)
                run.link = url
                run.foregroundColor = color
                result.append(run)
            } else {
                result.append(AttributedString(token.text))
            }
        }
        return result
    }
}

// MARK: - マークダウン英文のタップ対応

/// マークダウン英文（OCR結果など）を、見出しハイライト等の書式を保ったまま単語ごとに
/// タップ可能にする。単語だけを `eslword://` リンク化した文字列を `Markdown` に渡し、
/// リンクの見た目を本文と同一化（色 `.primary`・下線なし）してから `openURL` を横取りする。
/// MarkdownUI はリンクを標準の `AttributedString.link` で描くだけなので、プレーン英文と
/// 同じ仕組みでタップを検出できる。
struct TappableMarkdown: View {
    let markdown: String
    @Environment(\.wordTapAction) private var wordTapAction

    var body: some View {
        Markdown(EnglishWordLink.linkedMarkdown(markdown))
            .markdownHeadingHighlight()
            .markdownTextStyle(\.link) {
                ForegroundColor(.primary)
                UnderlineStyle(nil)
            }
            // foregroundColor だけでは環境によってリンクが tint 色を拾うことがあるため併用する
            .tint(.primary)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == EnglishWordLink.scheme else { return .systemAction }
                guard let word = EnglishWordLink.word(from: url) else { return .discarded }
                wordTapAction(word)
                return .handled
            })
    }
}

// MARK: - 登録モディファイア

/// 英文タップ登録の状態（確認ダイアログ・詳細遷移・トースト）を集約し、`\.wordTapAction` を
/// 環境へ注入するモディファイア。タップ対応したい画面のルートに `.wordTapRegistration(...)`
/// を付けるだけで、配下の `TappableEnglishText`/`TappableMarkdown` が機能する。
///
/// - 既に登録済みの単語をタップ → その単語詳細へ遷移（今表示中の単語自身はスキップ）。
/// - 未登録語をタップ → 追加確認ダイアログ → `WordRegistrar` で登録 → トースト表示。
struct WordRegistrationModifier: ViewModifier {
    /// 今表示中の単語（自分自身への遷移を避けるため）。WordDetailView から渡す。
    var currentWord: Word?
    /// 出現元の写真（OCR文脈をAI生成へ渡すため）。PhotoDetailView から渡す。
    var sourcePhoto: Photo?
    /// 紐付けるレッスン。指定時は出現記録を作る。
    var lesson: Lesson?

    @Environment(\.modelContext) private var modelContext
    @Query private var allWords: [Word]

    @State private var pendingWord: String?
    @State private var navigateToWord: Word?
    @State private var feedback: String?

    func body(content: Content) -> some View {
        content
            .environment(\.wordTapAction, WordTapAction(handleTap))
            .navigationDestination(item: $navigateToWord) { tapped in
                WordDetailView(word: tapped)
            }
            .overlay(alignment: .bottom) {
                if let feedback {
                    Text(feedback)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(radius: 4, y: 2)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: feedback)
            .task(id: feedback) {
                guard feedback != nil else { return }
                try? await Task.sleep(for: .seconds(1.6))
                feedback = nil
            }
            .confirmationDialog(
                "Add to word list?",
                isPresented: Binding(
                    get: { pendingWord != nil },
                    set: { if !$0 { pendingWord = nil } }
                ),
                presenting: pendingWord
            ) { word in
                Button("Add “\(word)”") { register(word) }
                Button("Cancel", role: .cancel) { pendingWord = nil }
            } message: { word in
                Text("Add “\(word)” to your word list?")
            }
    }

    /// タップされた単語の振り分け。登録済みなら詳細へ、未登録なら確認ダイアログを出す。
    private func handleTap(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let existing = allWords.first(where: {
            $0.text.compare(text, options: [.caseInsensitive]) == .orderedSame
        }) {
            guard existing.id != currentWord?.id else { return }
            navigateToWord = existing
        } else {
            pendingWord = text
        }
    }

    /// 確認後に単語を登録し、結果をトーストで知らせる。
    private func register(_ rawText: String) {
        guard let result = WordRegistrar.register(
            text: rawText,
            in: modelContext,
            existingWords: allWords,
            lesson: lesson,
            sourcePhoto: sourcePhoto
        ) else { return }
        feedback = result.isNew
            ? "Added “\(result.word.text)”"
            : "Already added: “\(result.word.text)”"
    }
}

extension View {
    /// 配下の `TappableEnglishText`/`TappableMarkdown` の単語タップを、登録・詳細遷移に接続する。
    func wordTapRegistration(
        currentWord: Word? = nil,
        sourcePhoto: Photo? = nil,
        lesson: Lesson? = nil
    ) -> some View {
        modifier(WordRegistrationModifier(
            currentWord: currentWord,
            sourcePhoto: sourcePhoto,
            lesson: lesson
        ))
    }
}

// MARK: - マークダウン見出しハイライト（PhotoDetailView から移設・共通化）

extension View {
    /// OCR結果・翻訳結果の本文中に埋め込まれたMarkdown見出し（`#`〜`###`）を、
    /// 背景色付きのラベルとして表示し、地の文と区別しやすくする。
    func markdownHeadingHighlight() -> some View {
        self
            .markdownBlockStyle(\.heading1) { markdownHeadingLabel($0, fontSize: .em(1.6), opacity: 0.18) }
            .markdownBlockStyle(\.heading2) { markdownHeadingLabel($0, fontSize: .em(1.35), opacity: 0.14) }
            .markdownBlockStyle(\.heading3) { markdownHeadingLabel($0, fontSize: .em(1.15), opacity: 0.1) }
    }
}

@MainActor
@ViewBuilder
private func markdownHeadingLabel(
    _ configuration: BlockConfiguration,
    fontSize: RelativeSize,
    opacity: Double
) -> some View {
    configuration.label
        .markdownTextStyle {
            FontWeight(.bold)
            FontSize(fontSize)
        }
        .relativePadding(.horizontal, length: .em(0.6))
        .relativePadding(.vertical, length: .em(0.3))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(opacity), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .markdownMargin(top: .em(1.2), bottom: .em(0.6))
}
