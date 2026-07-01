import SwiftUI
import SwiftData

struct WordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.registeredAt, order: .reverse) private var words: [Word]

    @State private var isShowingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(words) { word in
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
        }
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
        for index in offsets {
            modelContext.delete(words[index])
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
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self], inMemory: true)
}
