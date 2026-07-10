import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// `.fileImporter` で選ばれたURL群を、レッスン選択シート（`DocumentImportLessonView`）へ
/// 渡すための識別可能ラッパ。`.sheet(item:)` で扱えるようにする。
private struct PendingDocumentImport: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Content タブの Documents セグメント。iOSの「ファイル」（iCloud・端末内等）から取り込んだ文書
/// （PDF/DOCX＝`Document`）のライブラリ。行タップで詳細へ遷移し、詳細で原本表示・抽出＋翻訳・
/// タイトル編集・レッスン割当・削除を行う。音声の `AudioLibraryView` の文書版。
/// `ContentTabView` の NavigationStack 配下に埋め込む前提（自前の NavigationStack は持たない）。
struct DocumentLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Document.importedAt, order: .reverse) private var documents: [Document]

    @State private var isShowingFileImporter = false
    /// ファイル選択後、レッスン選択シートへ渡す取り込み待ちURL群
    @State private var pendingImport: PendingDocumentImport?
    @State private var importError: String?
    /// 詳細へ push 中の文書（行タップで設定 → navigationDestination で遷移）
    @State private var selectedDocument: Document?

    /// 取り込みで受け付ける形式（PDF / DOCX）。DOCX は system 宣言の型を優先し、取れなければ拡張子から解決する。
    private static let documentContentTypes: [UTType] = {
        var types: [UTType] = [.pdf]
        if let docx = UTType("org.openxmlformats.wordprocessingml.document")
            ?? UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        return types
    }()

    var body: some View {
        Group {
            if documents.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(documents) { document in
                        Button {
                            selectedDocument = document
                        } label: {
                            DocumentRow(document: document)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) { delete(document) }
                        }
                    }
                    .onDelete(perform: deleteAt)
                }
                .navigationDestination(item: $selectedDocument) { document in
                    DocumentDetailView(document: document)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingFileImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Import Document")
                .accessibilityIdentifier("documentImportButton")
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: Self.documentContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileSelection(result)
        }
        // ファイル選択後にレッスンを選んでから取り込む
        .sheet(item: $pendingImport) { pending in
            DocumentImportLessonView(urls: pending.urls) { lesson in
                importFiles(pending.urls, into: lesson)
            }
        }
        .alert("Import Failed", isPresented: importErrorBinding) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No documents yet", systemImage: "doc.text")
        } description: {
            Text("Import a PDF or Word file from the Files app (iCloud, on-device).")
        } actions: {
            Button("Import Document") { isShowingFileImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }

    /// ファイル選択の結果を受け取る。成功時は即取り込まず、レッスン選択シートへ回す。
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            pendingImport = PendingDocumentImport(urls: urls)
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    /// レッスン選択シートで確定した後に、実際の取り込みを行う。
    private func importFiles(_ urls: [URL], into lesson: Lesson?) {
        let count = DocumentFileImporter.importFiles(urls, into: lesson, context: modelContext)
        if count == 0 && !urls.isEmpty {
            importError = "Could not read the selected document(s)."
        }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private func deleteAt(_ offsets: IndexSet) {
        for index in offsets { delete(documents[index]) }
    }

    private func delete(_ document: Document) {
        // 原本ファイル削除・document 削除・sourceDocument の nullify・保存をまとめて行う
        modelContext.deleteDocument(document)
    }
}

/// 文書ライブラリ 1 行。タイトル＋紐付くレッスン名（あれば）＋抽出状態バッジ。
/// `AudioClipRow` の文書版。`DocumentsView` と `LessonsView` で共用する。
struct DocumentRow: View {
    let document: Document

    /// 紐付くレッスンのサブタイトル。複数時は先頭＋ "+N"。未割当は nil。
    private var lessonSubtitle: String? {
        let lessons = document.lessons.sorted { $0.date > $1.date }
        guard let first = lessons.first else { return nil }
        let base = "\(first.schoolClass.name) / \(first.title)"
        return lessons.count > 1 ? "\(base)  +\(lessons.count - 1)" : base
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: document.fileKind == .pdf ? "doc.richtext" : "doc.text")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title).lineLimit(1)
                if let subtitle = lessonSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 抽出の状態を控えめに示す（未実行は何も出さない）
            extractStatusBadge

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.25), value: document.processingStatus)
    }

    /// 抽出状態のミニインジケータ。完了=テキスト、処理中=スピナー、失敗=警告、未実行=なし。
    @ViewBuilder
    private var extractStatusBadge: some View {
        switch document.processingStatus {
        case .completed:
            Image(systemName: "text.alignleft")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .processing:
            ProgressView()
                .controlSize(.mini)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .pending:
            EmptyView()
        }
    }
}
