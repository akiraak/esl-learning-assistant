import MarkdownUI
import SwiftData
import SwiftUI

// MARK: - タップハンドラの環境値

/// 英文中の単語がタップされたときに呼ばれるアクション。SwiftUI の `OpenURLAction` に倣い、
/// 環境値としてビュー階層へ配布する。これにより深い階層（`WordAIInfoSections` など）へ
/// `onWordTap` をバケツリレーせずに済む。`WordRegistrationModifier` が実体を注入する。
/// `context` はタップ語を含む文（熟語自動判定のヒント。取得できない場合は nil）。
// クロージャは SwiftUI のビュー（MainActor）からのみ生成・呼び出しされるため unchecked Sendable でよい。
// 環境キーの defaultValue が Sendable を要求するための宣言。
struct WordTapAction: @unchecked Sendable {
    private let action: (String, String?) -> Void

    init(_ action: @escaping (String, String?) -> Void) {
        self.action = action
    }

    func callAsFunction(_ word: String, context: String? = nil) {
        action(word, context)
    }
}

private struct WordTapActionKey: EnvironmentKey {
    // 既定は何もしない（登録モディファイアが無い画面ではタップしても無反応）
    static let defaultValue = WordTapAction { _, _ in }
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
                guard let tap = EnglishWordLink.tapPayload(from: url) else { return .discarded }
                // タップ語を含む文を切り出して熟語自動判定のヒントに渡す（オフセット無しリンクは文脈なし）
                let context = tap.offset.flatMap {
                    EnglishWordLink.sentenceContext(in: text, around: $0, wordLength: tap.word.count)
                }
                wordTapAction(tap.word, context: context)
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var offset = 0
        for token in EnglishWordLink.tokenize(text) {
            if token.isWord,
               let core = EnglishWordLink.core(of: token.text),
               let url = EnglishWordLink.linkURL(for: core, offset: offset) {
                var run = AttributedString(token.text)
                run.link = url
                run.foregroundColor = color
                result.append(run)
            } else {
                result.append(AttributedString(token.text))
            }
            offset += token.text.count
        }
        return result
    }
}

// MARK: - マークダウン英文のタップ対応

/// マークダウン英文（OCR・文字起こし結果など）を、見出し/箇条書き/強調の書式を保ったまま
/// 単語ごとにタップ可能にする。
///
/// **なぜ MarkdownUI を使わないか**: MarkdownUI は1段落をインラインノード毎に `Text + Text` で連結する。
/// 全単語をリンク化すると段落あたりのノードが数百〜千になり、`ConcatenatedTextStorage` の深いネストを
/// `Text.resolve` が再帰処理して実機の ~1MB メインスレッドスタックを溢れさせ、`EXC_BAD_ACCESS`
/// （Thread stack size exceeded）でクラッシュする（シミュレータは ~8MB あり無再現。
/// [[markdownui-perword-link-stack-overflow]]）。そこで `MarkdownLite` で**ブロック**へ分解し、各ブロックを
/// **1つの `Text(AttributedString)`**（連結ゼロ＝再帰なし）で描くことで、段落の語数に依らず落ちないようにする。
/// タップ検出は `TappableEnglishText` と同じく `AttributedString.link` + `openURL` 横取りで行う。
struct TappableMarkdown: View {
    let markdown: String
    /// 単語（リンク）の文字色。標準の青リンク色を避け、本文と同じ見た目にするため明示指定する。
    var wordColor: Color = .primary
    @Environment(\.wordTapAction) private var wordTapAction

    private var blocks: [MarkdownLite.Block] { MarkdownLite.blocks(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index], blockIndex: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == EnglishWordLink.scheme else { return .systemAction }
            guard let tap = EnglishWordLink.tapPayload(from: url) else { return .discarded }
            wordTapAction(tap.word, context: sentenceContext(for: tap))
            return .handled
        })
    }

    /// タップ語を含む文をブロックの素文から切り出す（熟語自動判定のヒント）。
    /// 素文は spans の text 連結で、`attributedString(from:blockIndex:)` が数えたオフセットと
    /// 厳密に一致する。位置情報が無い・ブロック番号が範囲外なら nil（文脈なしで登録に進む）。
    private func sentenceContext(for tap: EnglishWordLink.TapPayload) -> String? {
        guard let blockIndex = tap.blockIndex, let offset = tap.offset else { return nil }
        let blocks = self.blocks
        guard blocks.indices.contains(blockIndex) else { return nil }
        let spans: [MarkdownLite.Span] = switch blocks[blockIndex] {
        case .heading(_, let spans), .bullet(let spans), .paragraph(let spans): spans
        }
        let blockText = spans.map(\.text).joined()
        return EnglishWordLink.sentenceContext(in: blockText, around: offset, wordLength: tap.word.count)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownLite.Block, blockIndex: Int) -> some View {
        switch block {
        case .heading(let level, let spans):
            headingView(level: level, spans: spans, blockIndex: blockIndex)
        case .bullet(let spans):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(attributedString(from: spans, blockIndex: blockIndex))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .paragraph(let spans):
            Text(attributedString(from: spans, blockIndex: blockIndex))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 見出しブロック。地の文と区別できるよう大きめ太字＋背景色（旧 `markdownHeadingHighlight` の見た目を踏襲）。
    private func headingView(level: Int, spans: [MarkdownLite.Span], blockIndex: Int) -> some View {
        let font: Font = level == 1 ? .title2 : (level == 2 ? .title3 : .headline)
        let opacity: Double = level == 1 ? 0.18 : (level == 2 ? 0.14 : 0.10)
        return Text(attributedString(from: spans, blockIndex: blockIndex))
            .font(font)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(opacity), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.top, 4)
    }

    /// スパン列を1つの `AttributedString` にする（全単語を `eslword://` リンク化＋強調フォント）。
    /// `Text + Text` の連結を使わないため、段落の語数に依らず `Text.resolve` の再帰でスタックを溢れさせない。
    /// リンクにはブロック番号とブロック素文内のオフセットを載せ、タップ時に文脈（文）を切り出す。
    private func attributedString(from spans: [MarkdownLite.Span], blockIndex: Int) -> AttributedString {
        var result = AttributedString()
        var offset = 0
        for span in spans {
            let spanFont = swiftUIFont(for: span.style)
            for token in EnglishWordLink.tokenize(span.text) {
                var run = AttributedString(token.text)
                if let spanFont { run.font = spanFont }
                if token.isWord,
                   let core = EnglishWordLink.core(of: token.text),
                   let url = EnglishWordLink.linkURL(for: core, offset: offset, blockIndex: blockIndex) {
                    run.link = url
                    run.foregroundColor = wordColor
                }
                result.append(run)
                offset += token.text.count
            }
        }
        return result
    }

    private func swiftUIFont(for style: MarkdownLite.InlineStyle) -> Font? {
        switch style {
        case .normal: return nil
        case .bold: return .body.bold()
        case .italic: return .body.italic()
        case .boldItalic: return .body.bold().italic()
        }
    }
}

// MARK: - 登録モディファイア

/// 英文タップ登録の状態（確認ダイアログ・詳細遷移・トースト）を集約し、`\.wordTapAction` を
/// 環境へ注入するモディファイア。タップ対応したい画面のルートに `.wordTapRegistration(...)`
/// を付けるだけで、配下の `TappableEnglishText`/`TappableMarkdown` が機能する。
///
/// - 既に登録済みの単語をタップ → その単語詳細へ遷移（今表示中の単語自身はスキップ）。
/// - 未登録語をタップ → 正規化（原形化・綴り訂正）を挟み、訂正候補があれば確認ダイアログ
///   （主=正規化形 / 逃げ道=入力形 / Cancel）を出す。訂正が無ければそのまま `WordRegistrar`
///   で登録し、結果をトーストで知らせる。正規化形が既存語と一致すれば重複としてその詳細へ遷移（dedup）。
///   判定ロジック（確認/即登録の出し分け・失敗フォールバック）は Add Word と共通の
///   `WordNormalizationFlow` に集約している。
struct WordRegistrationModifier: ViewModifier {
    /// 今表示中の単語（自分自身への遷移を避けるため）。WordDetailView から渡す。
    var currentWord: Word?
    /// 出現元の写真（OCR文脈をAI生成へ渡すため）。PhotoDetailView から渡す。
    var sourcePhoto: Photo?
    /// 出現元の音声クリップ（transcript 文脈をAI生成へ渡すため）。AudioDetailView から渡す。
    var sourceAudio: AudioClip?
    /// 出現元の文書（抽出テキスト文脈をAI生成へ渡すため）。DocumentDetailView から渡す。
    var sourceDocument: Document?
    /// 紐付けるレッスン。指定時は出現記録を作る。
    var lesson: Lesson?

    @Environment(\.modelContext) private var modelContext
    @Query private var allWords: [Word]

    /// 訂正候補（原形/正しい綴り）が出たときの確認ダイアログ用。nil でダイアログ非表示。
    @State private var pendingConfirmation: WordNormalization?
    /// 正規化待ち中の語。非 nil の間は追加タップで登録処理を重ねない（二重登録・多重ダイアログ防止）。
    /// どの語のリクエストか（誤タップ・遅延ダイアログの誤帰属）をトーストで示すため語そのものを持つ。
    @State private var normalizingWord: String?
    @State private var navigateToWord: WordRoute?
    @State private var feedback: String?

    /// 遷移先の単語を包む専用型。`navigationDestination(item:)` の型を `Word` そのものではなく
    /// この型にすることで、既に `Word` 型の navigationDestination を持つ画面（LessonsView 等）と
    /// 同一スタックで衝突しない（同一型の二重宣言による警告・片方の無効化を避ける）。
    private struct WordRoute: Identifiable, Hashable {
        let word: Word
        var id: UUID { word.id }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.wordTapAction, WordTapAction(handleTap))
            .navigationDestination(item: $navigateToWord) { route in
                WordDetailView(word: route.word)
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
            // 訂正候補（原形/正しい綴り）の確認。主=正規化形 / 逃げ道=入力形 / Cancel。
            // Add Word フォームと同一の文言・構成（説明 reason のみ母語）。
            .confirmationDialog(
                "Register the suggested form?",
                isPresented: Binding(
                    get: { pendingConfirmation != nil },
                    set: { if !$0 { pendingConfirmation = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingConfirmation
            ) { normalization in
                Button("Register “\(normalization.effectiveLemma)”") { register(normalization.effectiveLemma) }
                Button("Keep “\(normalization.input)”") { register(normalization.input) }
                Button("Cancel", role: .cancel) {}
            } message: { normalization in
                Text(normalization.reason)
            }
    }

    /// タップされた単語の振り分け。
    /// 1. 入力語そのものが登録済み → 即詳細へ（正規化不要の最速パス・オフラインでも動く。
    ///    このパスでは熟語判定はしない）。
    /// 2. 未登録語 → 正規化（原形化・綴り訂正・文脈からの熟語判定）を挟み、
    ///    `WordNormalizationFlow.decide` の結果で分岐する。
    ///    - 訂正なし（canonical/固有名詞/連語/判定不能/失敗フォールバック）→ そのまま登録。
    ///    - 訂正あり（原形・正しい綴り・熟語 “look up” の提案）→ 正規化形が既存語なら重複として
    ///      その詳細へ集約、無ければ確認ダイアログ。
    /// - Parameter context: タップ語を含む文（`TappableEnglishText`/`TappableMarkdown` が切り出す）。
    ///   熟語自動判定のヒントとして正規化 API へ渡す。
    private func handleTap(_ rawText: String, context: String?) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 正規化待ち中の追加タップは登録処理を重ねない（二重登録・多重ダイアログを防ぐ）。
        // 黙殺すると、後から出る確認ダイアログが「いま触った語への応答」に見えてしまうため、
        // 処理中の語をトーストで知らせて誤帰属を防ぐ。
        if let normalizingWord {
            feedback = "Checking “\(normalizingWord)”…"
            return
        }
        // 入力語そのものが既に登録済みなら正規化せず即詳細へ
        if let existing = existingWord(matching: text) {
            navigate(to: existing)
            return
        }

        // どの語のリクエストかを即時に可視化する（誤タップにもすぐ気づける）
        normalizingWord = text
        feedback = "Checking “\(text)”…"
        let service = RemoteWordNormalizeService()
        Task {
            let decision = await WordNormalizationFlow.decide(
                input: text,
                targetLanguage: WordNormalizationFlow.targetLanguage,
                context: context,
                using: service
            )
            normalizingWord = nil
            switch decision {
            case .registerImmediately(let resolved):
                register(resolved)
            case .confirm(let normalization):
                // 正規化形が既存語なら重複 → 確認を出さず既存詳細へ集約（dedup）
                if let existing = existingWord(matching: normalization.effectiveLemma) {
                    navigate(to: existing)
                } else {
                    // 「Checking…」トーストは片付けてからダイアログを出す（下端で重なるため）
                    feedback = nil
                    pendingConfirmation = normalization
                }
            }
        }
    }

    /// 大文字小文字を無視して同綴りの既存単語を探す（登録の集約・重複判定に使う）。
    private func existingWord(matching text: String) -> Word? {
        allWords.first {
            $0.text.compare(text, options: [.caseInsensitive]) == .orderedSame
        }
    }

    /// 既存単語の詳細へ遷移する。今表示中の単語自身への遷移はスキップする。
    private func navigate(to word: Word) {
        guard word.id != currentWord?.id else { return }
        navigateToWord = WordRoute(word: word)
    }

    /// 確認後に単語を登録し、結果をトーストで知らせる。
    private func register(_ rawText: String) {
        guard let result = WordRegistrar.register(
            text: rawText,
            in: modelContext,
            existingWords: allWords,
            lesson: lesson,
            sourcePhoto: sourcePhoto,
            sourceAudio: sourceAudio,
            sourceDocument: sourceDocument
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
        sourceAudio: AudioClip? = nil,
        sourceDocument: Document? = nil,
        lesson: Lesson? = nil
    ) -> some View {
        modifier(WordRegistrationModifier(
            currentWord: currentWord,
            sourcePhoto: sourcePhoto,
            sourceAudio: sourceAudio,
            sourceDocument: sourceDocument,
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
