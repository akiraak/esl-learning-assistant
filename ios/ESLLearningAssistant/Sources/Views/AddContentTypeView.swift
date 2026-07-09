import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// コンテンツ追加の入口。「＋」タップで最初に出るタイプ選択シート。
/// 写真 / Audio / YouTube の3択を並べ、選択に応じて既存の追加 UI を提示する。
/// - 写真: 既存 `CaptureView`（撮影・ライブラリ選択）
/// - Audio: 既存 `.fileImporter`
/// - YouTube: 新規 `YouTubeAddView`（動画ID / URL 入力）
///
/// いずれかの追加が完了したら、このシート全体を閉じてレッスン画面へ戻す
/// （内側シートを閉じた `onDismiss` で `didComplete` を見て外側も閉じる）。
struct AddContentTypeView: View {
    /// 追加先のレッスン
    let lesson: Lesson
    /// 写真を追加し終えたら呼ぶ。OCR/翻訳は永続する呼び出し元（LessonsView）で実行させる。
    var onPhotoAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingCapture = false
    @State private var isShowingAudioImporter = false
    @State private var isShowingDocumentImporter = false
    @State private var isShowingYouTubeAdd = false
    /// 内側フローが「追加完了」で閉じたか。true なら内側の `onDismiss` で外側シートも閉じる。
    @State private var didComplete = false
    @State private var audioImportError: String?
    @State private var documentImportError: String?

    /// ドキュメント取り込みで受け付ける形式（PDF / DOCX）。DOCX は system 宣言の型を優先し、
    /// 取れなければ拡張子から解決する。
    private static let documentContentTypes: [UTType] = {
        var types: [UTType] = [.pdf]
        if let docx = UTType("org.openxmlformats.wordprocessingml.document")
            ?? UTType(filenameExtension: "docx") {
            types.append(docx)
        }
        return types
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    typeRow(
                        title: "Photo",
                        subtitle: "Capture or choose a textbook page",
                        systemImage: "photo",
                        tint: .blue,
                        identifier: "addContentPhotoButton"
                    ) { isShowingCapture = true }

                    typeRow(
                        title: "Audio",
                        subtitle: "Import an audio file",
                        systemImage: "waveform",
                        tint: .orange,
                        identifier: "addContentAudioButton"
                    ) { isShowingAudioImporter = true }

                    typeRow(
                        title: "Document",
                        subtitle: "Import a PDF or Word file",
                        systemImage: "doc.text",
                        tint: .green,
                        identifier: "addContentDocumentButton"
                    ) { isShowingDocumentImporter = true }

                    typeRow(
                        title: "YouTube",
                        subtitle: "Add by video ID or URL",
                        systemImage: "play.rectangle.fill",
                        tint: .red,
                        identifier: "addContentYouTubeButton"
                    ) { isShowingYouTubeAdd = true }
                }
            }
            .navigationTitle("Add Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingCapture, onDismiss: dismissIfCompleted) {
                CaptureView(lesson: lesson) { _ in
                    // 写真は pending 登録済み。翻訳は呼び出し元で走らせ、フロー全体を閉じる。
                    onPhotoAdded()
                    didComplete = true
                }
            }
            .sheet(isPresented: $isShowingYouTubeAdd, onDismiss: dismissIfCompleted) {
                YouTubeAddView(lesson: lesson) {
                    didComplete = true
                }
            }
            .fileImporter(
                isPresented: $isShowingAudioImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleAudioImport(result)
            }
            .fileImporter(
                isPresented: $isShowingDocumentImporter,
                allowedContentTypes: Self.documentContentTypes,
                allowsMultipleSelection: true
            ) { result in
                handleDocumentImport(result)
            }
            .alert("Import Failed", isPresented: audioImportErrorBinding) {
                Button("OK", role: .cancel) { audioImportError = nil }
            } message: {
                Text(audioImportError ?? "")
            }
            .alert("Import Failed", isPresented: documentImportErrorBinding) {
                Button("OK", role: .cancel) { documentImportError = nil }
            } message: {
                Text(documentImportError ?? "")
            }
        }
    }

    private func typeRow(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// 内側フローが完了で閉じたときだけ、外側シート全体を閉じてレッスンへ戻す。
    private func dismissIfCompleted() {
        if didComplete { dismiss() }
    }

    private var audioImportErrorBinding: Binding<Bool> {
        Binding(get: { audioImportError != nil }, set: { if !$0 { audioImportError = nil } })
    }

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let count = AudioFileImporter.importFiles(urls, into: lesson, context: modelContext)
            if count == 0 && !urls.isEmpty {
                audioImportError = "Could not read the selected audio file(s)."
            } else if count > 0 {
                // 取り込めたらフロー全体を閉じてレッスンへ戻す
                dismiss()
            }
        case .failure(let error):
            audioImportError = error.localizedDescription
        }
    }

    private var documentImportErrorBinding: Binding<Bool> {
        Binding(get: { documentImportError != nil }, set: { if !$0 { documentImportError = nil } })
    }

    private func handleDocumentImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // 抽出＋翻訳は Document 詳細（Phase 4）の手動ボタンで走らせる。ここでは pending で取り込むだけ。
            let count = DocumentFileImporter.importFiles(urls, into: lesson, context: modelContext)
            if count == 0 && !urls.isEmpty {
                documentImportError = "Could not read the selected document(s)."
            } else if count > 0 {
                // 取り込めたらフロー全体を閉じてレッスンへ戻す
                dismiss()
            }
        case .failure(let error):
            documentImportError = error.localizedDescription
        }
    }
}
