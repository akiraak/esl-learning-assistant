import SwiftUI
import SwiftData

struct WordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: \Word.registeredAt, order: .reverse) private var words: [Word]

    @State private var isShowingAdd = false
    @State private var searchText = ""
    @State private var pushedWord: Word?
    @State private var isBulkGenerating = false
    @State private var bulkDone = 0
    @State private var bulkTotal = 0

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
            .navigationTitle("Words")
            .searchable(text: $searchText, prompt: "Search words")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAdd = true
                    } label: {
                        Label("Add Word", systemImage: "plus")
                    }
                    .accessibilityIdentifier("wordAddButton")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        generateAllPending()
                    } label: {
                        Label("Generate Missing AI Info", systemImage: "sparkles")
                    }
                    .disabled(isBulkGenerating || pendingAIWords.isEmpty)
                    .accessibilityIdentifier("wordBulkGenerateButton")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isBulkGenerating {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Generating AI info (\(bulkDone)/\(bulkTotal))")
                            .font(.footnote)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
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

    /// AI情報が未生成・生成失敗の単語
    private var pendingAIWords: [Word] {
        words.filter { $0.aiInfoStatus == .none || $0.aiInfoStatus == .failed }
    }

    /// 未生成・失敗の単語のAI情報を順次生成する（並列にせずAPI負荷を抑える）
    private func generateAllPending() {
        let targets = pendingAIWords
        guard !targets.isEmpty, !isBulkGenerating else { return }
        isBulkGenerating = true
        bulkTotal = targets.count
        bulkDone = 0
        Task {
            for word in targets {
                // 生成中にユーザーが削除した単語はスキップする
                guard word.modelContext != nil else {
                    bulkDone += 1
                    continue
                }
                await WordAIInfoGenerator.shared.generate(for: word)
                bulkDone += 1
            }
            isBulkGenerating = false
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
            Text("No Words")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Add words you come across in your textbooks and lessons.")
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(word.text)
                    .font(.headline)
                // 訳語はAI生成完了時に自動補完されるため、それまでは空（行を出さない）
                if !word.translation.isEmpty {
                    Text(word.translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
        .environment(AppRouter())
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
