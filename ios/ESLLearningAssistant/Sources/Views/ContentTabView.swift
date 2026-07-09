import SwiftUI

/// Content タブのトップ。取り込んだ学習コンテンツのライブラリをセグメントで切り替えて一覧する。
/// タブを5個以下に保つため Audio / Documents タブを統合したもの（6個以上だと iOS の More タブに
/// 入り、More のナビゲーションバーと NavigationStack が二重になる）。
/// 将来 YouTube の横断一覧セグメントを追加する（docs/plans/content-tab.md）。
struct ContentTabView: View {
    /// セグメントで切り替えるコンテンツ種別
    private enum ContentKind: Hashable {
        case photos
        case audio
        case documents
    }

    @State private var kind: ContentKind = .photos
    /// 音声の再生サービス。詳細画面へ push しても再生を継続できるよう、push で消えない
    /// この階層で保持する。タブ離脱・セグメント切替で停止する。
    @StateObject private var playback = TTSPlaybackService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Content Type", selection: $kind) {
                    Text("Photos").tag(ContentKind.photos)
                    Text("Audio").tag(ContentKind.audio)
                    Text("Documents").tag(ContentKind.documents)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 4)

                switch kind {
                case .photos:
                    PhotoLibraryView()
                case .audio:
                    AudioLibraryView(playback: playback)
                case .documents:
                    DocumentLibraryView()
                }
            }
            .navigationTitle("Content")
        }
        // 再生UIは AudioDetailView の safeAreaInset に集約する（一覧には出さない）
        .onDisappear { playback.stop() }
        .onChange(of: kind) { playback.stop() }
    }
}
