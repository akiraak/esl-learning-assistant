import MarkdownUI
import SwiftUI
import SwiftData

/// 文書（PDF/DOCX）の詳細。原本のアプリ内表示（PDFView/QuickLook）・抽出＋翻訳・
/// 抽出英文の単語タップ登録・訳の Markdown 表示・レッスンの追加/解除・削除をこの画面に集約する。
/// 音声の `AudioDetailView` の文書版（再生の代わりに原本ビューアを持つ）。
struct DocumentDetailView: View {
    @Bindable var document: Document

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isAddingLesson = false
    @State private var isConfirmingDelete = false
    /// 原本を全画面ビューアで開いているか
    @State private var isShowingFullScreenViewer = false
    /// サーバTTS失敗で端末内蔵TTSへフォールバックしたときに、控えめな告知を数秒だけ表示する
    @State private var isUsingFallbackVoice = false
    @StateObject private var speechService = SpeechService()
    @StateObject private var ttsPlayback = TTSPlaybackService()

    /// 文書→英文抽出（テキスト層 or スキャンOCR）＋翻訳。差し替え可能に protocol 型で保持する。
    private let extractService: DocumentExtractTranslateService = RemoteDocumentExtractTranslateService()

    private var fileURL: URL { DocumentStorage.url(fileName: document.documentFileName) }
    /// 単語タップ登録の紐付け先。紐付くレッスンのうち最新のものを使う（未割当なら nil）。
    private var primaryLesson: Lesson? {
        document.lessons.sorted { $0.createdAt > $1.createdAt }.first
    }

    var body: some View {
        Form {
            Section("Title") {
                TextField("Title", text: $document.title)
                    .onChange(of: document.title) { modelContext.saveOrLog() }
            }

            originalSection

            extractSection

            Section {
                // 音声詳細と同型：一覧＋スワイプ解除＋追加ボタン
                let linked = document.lessons.sorted { $0.createdAt > $1.createdAt }
                ForEach(linked) { lesson in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.title)
                            .foregroundStyle(.primary)
                        Text(lesson.schoolClass.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            unlink(lesson)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
                Button {
                    isAddingLesson = true
                } label: {
                    Label("Add to Lesson", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("documentAddToLessonButton")
            } header: {
                Text("Lessons")
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Document", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier("documentDeleteButton")
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.25), value: document.processingStatus)
        // 抽出英文の単語タップ→登録/詳細遷移。紐付くレッスンがあれば出現記録も残す。
        // sourceDocument にこの文書を渡し、AI 単語情報生成へ抽出テキストを文脈として渡せるようにする。
        .wordTapRegistration(sourceDocument: document, lesson: primaryLesson)
        .fullScreenCover(isPresented: $isShowingFullScreenViewer) {
            NavigationStack {
                DocumentFileViewer(document: document)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(document.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingFullScreenViewer = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isAddingLesson) {
            // 既にリンク済みのレッスンは除外して二重リンクを防ぐ
            let linkedLessonIDs = Set(document.lessons.map(\.id))
            WordLessonPickerView(excludedLessonIDs: linkedLessonIDs, title: "Add to Lesson") { lesson in
                link(lesson)
            }
        }
        .confirmationDialog(
            "Delete this document?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if ttsPlayback.isActive {
                TTSPlayerBar(playback: ttsPlayback)
            }
        }
        .animation(.snappy(duration: 0.2), value: ttsPlayback.isActive)
        .onDisappear {
            stopSpeaking()
        }
    }

    private func stopSpeaking() {
        speechService.stop()
        ttsPlayback.stop()
    }

    /// サーバTTSが使えないとき、端末内蔵TTSで読み上げつつ控えめな告知を数秒表示する
    private func fallBackToOnDeviceVoice(_ text: String) {
        speechService.speak(text)
        withAnimation(.snappy) { isUsingFallbackVoice = true }
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation(.snappy) { isUsingFallbackVoice = false }
        }
    }

    // MARK: - Original file viewer

    /// 原本表示セクション。PDF はインライン埋め込み、DOCX は全画面ボタン。
    /// どちらも「View Full Screen」で全画面ビューアを開ける。抽出前でも閲覧できる。
    @ViewBuilder
    private var originalSection: some View {
        Section {
            LabeledContent {
                Text(fileTypeLabel)
                    .foregroundStyle(.secondary)
            } label: {
                Label("File", systemImage: "doc")
            }

            switch document.fileKind {
            case .pdf:
                // テキスト層のある PDF はネイティブ描画でインラインプレビュー
                PDFViewer(url: fileURL)
                    .frame(height: 460)
                    .listRowInsets(EdgeInsets())
            case .docx:
                // DOCX はインライン描画が不向きなので全画面 QuickLook をボタンから開く
                EmptyView()
            }

            Button {
                isShowingFullScreenViewer = true
            } label: {
                Label(
                    document.fileKind == .pdf ? "View Full Screen" : "View Document",
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
            }
            .accessibilityIdentifier("documentViewFileButton")
        } header: {
            Text("Original")
        }
    }

    private var fileTypeLabel: String {
        let kind = document.fileKind == .pdf ? "PDF" : "Word"
        let megabytes = Double(document.byteSize) / 1024 / 1024
        return megabytes >= 0.1 ? String(format: "%@ · %.1f MB", kind, megabytes) : kind
    }

    // MARK: - Extract & translate

    /// 抽出＋翻訳セクション。`processingStatus` で表示を分岐する
    /// （未実行=手動ボタン / 処理中=インジケータ / 失敗=エラー＋再試行 / 完了=英文＋訳＋再実行）。
    @ViewBuilder
    private var extractSection: some View {
        Section {
            switch document.processingStatus {
            case .pending:
                extractButton(title: "Extract & Translate", systemImage: "doc.text.magnifyingglass")
            case .processing:
                ProcessingIndicatorView(label: "Extracting & translating…")
                    .padding(.vertical, 4)
            case .failed:
                VStack(alignment: .leading, spacing: 8) {
                    TappableEnglishText(text: "Extraction & translation failed", color: .red)
                        .foregroundStyle(.red)
                    if let message = document.processingErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    extractButton(title: "Try Again", systemImage: "arrow.clockwise")
                }
            case .completed:
                completedExtract
            }
        } header: {
            Text("Text")
        }
    }

    /// 完了時の本文表示：英文（単語タップ可）＋訳（Markdown）＋再実行ボタン。
    @ViewBuilder
    private var completedExtract: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TappableEnglishText(text: "Extracted Text (English)")
                    .font(.headline)
                Spacer()
                // AI音声（サーバTTS）の生成→キャッシュ→再生。写真詳細と同じ TTSButton を共有。
                // 生成失敗時は端末内蔵TTSへフォールバックする（onGenerateFailure）。
                TTSButton(
                    text: MarkdownPlainText.plainText(document.extractedText),
                    playback: ttsPlayback,
                    errorMessage: .constant(nil),
                    onGenerateFailure: {
                        fallBackToOnDeviceVoice(MarkdownPlainText.plainText(document.extractedText))
                    }
                )
            }
            if isUsingFallbackVoice {
                Label(
                    "Server voice unavailable — using on-device voice",
                    systemImage: "iphone"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
            TappableMarkdown(markdown: document.extractedText ?? "")

            Divider()

            TappableEnglishText(text: "Translation")
                .font(.headline)
            Markdown(document.translatedText ?? "")
                .markdownHeadingHighlight()

            Divider()

            extractButton(title: "Re-extract", systemImage: "arrow.clockwise")
        }
    }

    private func extractButton(title: String, systemImage: String) -> some View {
        Button {
            Task { await runExtraction() }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("documentExtractButton")
    }

    /// 抽出＋翻訳を実行する。サービスが `document` を更新し、明示保存で永続化する
    /// （autosave 任せだと直後にアプリを強制終了された場合に失われるため）。
    private func runExtraction() async {
        await extractService.process(document)
        modelContext.saveOrLog()
    }

    // MARK: - Lessons / delete

    /// レッスンに紐付ける（既にリンク済みなら何もしない）
    private func link(_ lesson: Lesson) {
        guard !document.lessons.contains(where: { $0.id == lesson.id }) else { return }
        document.lessons.append(lesson)
        modelContext.saveOrLog()
    }

    /// 指定レッスンとの紐付けを解除する（文書本体・レッスンは残る）
    private func unlink(_ lesson: Lesson) {
        document.lessons.removeAll { $0.id == lesson.id }
        modelContext.saveOrLog()
    }

    private func delete() {
        // 原本ファイル削除・document 削除・sourceDocument の nullify・保存をまとめて行う
        modelContext.deleteDocument(document)
        dismiss()
    }
}
