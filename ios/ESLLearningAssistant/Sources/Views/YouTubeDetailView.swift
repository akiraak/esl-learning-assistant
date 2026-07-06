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
            EmbeddedWebView(embedURL: embedURL)
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

/// SwiftUI から `WKWebView` を使う最小ラッパー。埋め込み URL を iframe として
/// ホストする HTML を1度だけ読み込む。
///
/// 直リンク（`load(URLRequest:)`）ではなく iframe を有効な http(s) オリジンの
/// `baseURL` で `loadHTMLString` することで、埋め込みプレイヤーに `Referer`/
/// オリジンが渡り、YouTube のエラー153（動画プレイヤーの設定エラー）を防ぐ。
/// インライン再生を許可し、自動再生はユーザー操作を必須にする（不意の音声を避ける）。
private struct EmbeddedWebView: UIViewRepresentable {
    let embedURL: URL

    /// iframe の `Referer` 元となる http(s) オリジン。空オリジンだと 153 になる。
    /// iframe と同一オリジンにしておく。
    private static let baseURL = URL(string: "https://www.youtube-nocookie.com")

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        // videoID は詳細画面の生存中は不変なので、ここで1度だけ読み込む。
        webView.loadHTMLString(Self.embedHTML(for: embedURL), baseURL: Self.baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 不変なので再読込しない（レイアウト更新のたびにリロードしない）。
    }

    /// embed URL を `src` に持つ iframe をレスポンシブに全面表示する最小 HTML。
    /// `referrerpolicy`/`<meta name="referrer">` で `Referer` を明示的に渡す。
    private static func embedHTML(for embedURL: URL) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
          html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
          iframe { display: block; width: 100%; height: 100%; border: 0; }
        </style>
        </head>
        <body>
          <iframe
            src="\(embedURL.absoluteString)"
            referrerpolicy="strict-origin-when-cross-origin"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen>
          </iframe>
        </body>
        </html>
        """
    }
}
