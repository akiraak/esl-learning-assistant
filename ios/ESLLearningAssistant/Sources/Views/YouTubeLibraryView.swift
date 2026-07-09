import SwiftUI
import SwiftData

/// Content タブの YouTube セグメント。全レッスンの YouTube リンクを横断して追加日の新しい順に一覧する。
/// 行タップで詳細（埋め込みプレイヤー）へ遷移する。写真の `PhotoLibraryView` の YouTube 版。
/// `ContentTabView` の NavigationStack 配下に埋め込む前提（自前の NavigationStack は持たない）。
/// YouTube はレッスン必須（to-one）のため、「+」の追加は `YouTubeAddView` 内のレッスン選択を経由する。
struct YouTubeLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \YouTubeLink.addedAt, order: .reverse) private var links: [YouTubeLink]

    @State private var isShowingAdd = false
    /// 詳細へ push 中のリンク（行タップで設定 → navigationDestination で遷移）
    @State private var selectedLink: YouTubeLink?

    var body: some View {
        Group {
            if links.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(links) { link in
                        Button {
                            selectedLink = link
                        } label: {
                            YouTubeRow(link: link, showsLesson: true)
                        }
                        .buttonStyle(.plain)
                        // リンクは再追加が容易なため、レッスン画面のスワイプ削除と同じく確認なしで消す
                        // （詳細画面の削除ボタン側には確認ダイアログがある）
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteLink(link)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .navigationDestination(item: $selectedLink) { link in
                    YouTubeDetailView(link: link)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add YouTube")
                .accessibilityIdentifier("youtubeAddButton")
            }
        }
        .sheet(isPresented: $isShowingAdd) {
            // レッスンはシート内のレッスン選択で選ぶ（既定は最新レッスン）
            YouTubeAddView()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No YouTube videos yet", systemImage: "play.rectangle")
        } description: {
            Text("Add a YouTube video by its video ID or URL.")
        } actions: {
            Button("Add YouTube") { isShowingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }

    /// YouTube リンクを削除する。to-one/cascade（レッスン固有）なので実体の後始末は不要。
    private func deleteLink(_ link: YouTubeLink) {
        modelContext.delete(link)
        modelContext.saveOrLog()
    }
}
