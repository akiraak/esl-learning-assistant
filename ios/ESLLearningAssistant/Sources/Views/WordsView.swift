import SwiftUI
import SwiftData

struct WordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: \Word.registeredAt, order: .reverse) private var words: [Word]

    @State private var isShowingAdd = false
    @State private var searchText = ""
    @State private var pushedWord: Word?

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    emptyState
                } else if filteredWords.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filteredWords) { word in
                            NavigationLink {
                                WordDetailView(word: word)
                            } label: {
                                WordRow(word: word)
                            }
                        }
                        .onDelete(perform: deleteWords)
                    }
                }
            }
            .navigationTitle("単語")
            .searchable(text: $searchText, prompt: "単語・訳語を検索")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Label("単語を追加", systemImage: "plus")
                    }
                    .accessibilityIdentifier("wordAddButton")
                }
            }
            .sheet(isPresented: $isShowingAdd) {
                WordAddView()
            }
            .navigationDestination(item: $pushedWord) { word in
                WordDetailView(word: word)
            }
            .onAppear(perform: consumePendingWord)
            .onChange(of: router.pendingWord) { _, _ in
                consumePendingWord()
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

    /// 他タブから指定された単語があれば詳細をプッシュする
    private func consumePendingWord() {
        guard let word = router.pendingWord else { return }
        router.pendingWord = nil
        pushedWord = word
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("単語がありません")
                .font(.title2)
                .fontWeight(.semibold)
            Text("教科書やレッスンで出会った単語を登録しましょう。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                isShowingAdd = true
            } label: {
                Label("単語を追加", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func deleteWords(at offsets: IndexSet) {
        let targets = filteredWords
        for index in offsets {
            modelContext.delete(targets[index])
        }
    }
}

struct WordRow: View {
    let word: Word

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(word.text)
                .font(.headline)
            Text(word.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    WordsView()
        .environment(AppRouter())
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
