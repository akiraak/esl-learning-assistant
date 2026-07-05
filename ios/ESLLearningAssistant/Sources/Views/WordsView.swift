import SwiftUI
import SwiftData

struct WordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.registeredAt, order: .reverse) private var words: [Word]

    @State private var isShowingAdd = false
    @State private var isShowingReview = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    emptyState
                } else if filteredWords.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        // 検索中は結果に集中させるため復習カードを出さない
                        if searchText.isEmpty {
                            todayReviewCard
                        }
                        // 単語本体の削除は詳細画面の Delete Word ボタンに集約する（スワイプ削除なし）
                        ForEach(filteredWords) { word in
                            NavigationLink {
                                WordDetailView(word: word)
                            } label: {
                                WordRow(word: word)
                            }
                        }
                    }
                }
            }
            .wordTapRegistration()
            .searchable(text: $searchText, prompt: "Search words")
            .overlay(alignment: .bottomTrailing) {
                // 空状態では中央の Add Word ボタンを使うため、一覧があるときだけ表示する
                if !words.isEmpty {
                    addFloatingButton
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                WordAddView()
            }
            .fullScreenCover(isPresented: $isShowingReview) {
                ReviewSessionView(dueWords: dueWords)
            }
        }
    }

    /// 今日の復習対象（dueDate がローカル日付で今日以前の単語）
    private var dueWords: [Word] {
        words.filter { ReviewScheduler.isDue($0.reviewState) }
    }

    /// List 先頭の「今日の復習」カード。対象0件なら完了表示に切り替わる（プラン §3.5）
    private var todayReviewCard: some View {
        Section {
            let dueCount = dueWords.count
            if dueCount > 0 {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        TappableEnglishText(text: "Today's Review")
                            .font(.headline)
                        TappableEnglishText(text: "\(dueCount) word\(dueCount == 1 ? "" : "s") to review", color: .secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Start") {
                        isShowingReview = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("reviewStartButton")
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Today's review is complete 🎉")
                        .font(.subheadline)
                        .accessibilityIdentifier("reviewCompleteLabel")
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// 検索文字列で見出し語・訳語を絞り込んだ一覧
    private var filteredWords: [Word] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return words }
        return words.filter {
            $0.text.localizedCaseInsensitiveContains(query)
                || $0.translation.localizedCaseInsensitiveContains(query)
        }
    }

    /// 右下に浮かべる単語追加ボタン
    private var addFloatingButton: some View {
        Button {
            isShowingAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .accessibilityLabel("Add Word")
        .accessibilityIdentifier("wordAddButton")
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            TappableEnglishText(text: "No Words")
                .font(.title2)
                .fontWeight(.semibold)
            TappableEnglishText(text: "Add words you come across in your textbooks and lessons.", color: .secondary)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                isShowingAdd = true
            } label: {
                Label("Add Word", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            // 空状態ではFABを出さないため、同じ識別子をこちらに付ける（UIテストが参照）
            .accessibilityIdentifier("wordAddButton")
        }
    }

}

struct WordRow: View {
    let word: Word

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text(word.text)
                    .font(.headline)
                    .lineLimit(1)
                    // 幅が足りないときは訳語側から省略する
                    .layoutPriority(1)
                // 訳語はAI生成完了時に自動補完されるため、それまでは空（表示しない）。
                // 複数品詞を持つ単語は listTranslation で他品詞の意味も「 / 」区切りで見せる。
                if !word.listTranslation.isEmpty {
                    Text(word.listTranslation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // AI情報の生成状態（completed / none は表示なし＝ノイズにしない）
            switch word.aiInfoStatus {
            case .generating:
                ProgressView()
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            case .none, .completed:
                EmptyView()
            }
        }
    }
}

#Preview {
    WordsView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
