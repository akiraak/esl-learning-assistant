import PDFKit
import QuickLook
import SwiftUI

/// 取り込んだ文書（PDF/DOCX）の原本をアプリ内で表示する薄い SwiftUI ラッパ。
/// `fileKind` で描画手段を出し分ける（PDF=PDFKit のネイティブ描画 / DOCX=QuickLook の Office 変換）。
/// 表示は抽出結果に依存しないため、pending/failed でも原本を閲覧できる。
/// システムフレームワーク（PDFKit / QuickLook）は `import` で暗黙リンクされる（project.yml 変更不要）。
struct DocumentFileViewer: View {
    let document: Document

    private var fileURL: URL { DocumentStorage.url(fileName: document.documentFileName) }

    var body: some View {
        Group {
            if DocumentStorage.exists(fileName: document.documentFileName) {
                switch document.fileKind {
                case .pdf:
                    PDFViewer(url: fileURL)
                case .docx:
                    // DOCX は HTML ではないため WKWebView 不可。QuickLook の内蔵 Office 変換で表示する。
                    QuickLookPreview(url: fileURL)
                }
            } else {
                ContentUnavailableView(
                    "File Unavailable",
                    systemImage: "doc.questionmark",
                    description: Text("The original document file could not be found.")
                )
            }
        }
    }
}

// MARK: - PDF（PDFKit）

/// `PDFKit.PDFView` を SwiftUI に埋め込む。スクロール/ズーム/ページ送り/テキスト選択を
/// ネイティブ描画で提供する。`url` は不変（同一文書の原本）なので `updateUIView` では作り直さない。
struct PDFViewer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // 別 URL に差し替わった場合だけ読み直す（通常は不変）。
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

// MARK: - DOCX 等（QuickLook）

/// `QLPreviewController` を SwiftUI に埋め込む。OS 内蔵のプレビュー（DOCX の Office 変換を含む）を使う。
/// 読み取り専用。データソースは `url` を1件だけ供給する。
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
