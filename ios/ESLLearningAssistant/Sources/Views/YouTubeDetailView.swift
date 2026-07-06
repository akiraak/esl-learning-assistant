import SwiftUI
import SwiftData
import WebKit

/// YouTube 動画の詳細。アプリ内の埋め込みプレイヤー（cookie を使わない nocookie ドメイン）で
/// 再生する。埋め込みが使えない場合に備え、YouTube アプリ/ブラウザで開くフォールバックも置く。
/// YouTube はレッスン固有・to-one/cascade（`Photo` と同型）なので、削除は `PhotoDetailView` に倣う。
struct YouTubeDetailView: View {
    let link: YouTubeLink

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                player

                if let watchURL = link.watchURL {
                    Button {
                        openURL(watchURL)
                    } label: {
                        Label("Open in YouTube", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                deleteButton
            }
            .padding()
        }
        .navigationTitle("YouTube")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var player: some View {
        if let embedURL = link.embedURL {
            EmbeddedWebView(url: embedURL)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            // embedURL が組めない異常時のフォールバック表示（実質発生しない）
            YouTubeThumbnail(videoID: link.videoID)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label("Delete YouTube Link", systemImage: "trash")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .confirmationDialog(
            "Delete this YouTube link?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(link)
                modelContext.saveOrLog()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the YouTube link from this lesson. This cannot be undone.")
        }
    }
}

/// SwiftUI から `WKWebView` を使う最小ラッパー。指定 URL を1度だけ読み込む。
/// YouTube 埋め込みのインライン再生を許可し、自動再生はユーザー操作を必須にする（不意の音声を避ける）。
private struct EmbeddedWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 同じ URL の再読込を避ける（レイアウト更新のたびにリロードしない）
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
