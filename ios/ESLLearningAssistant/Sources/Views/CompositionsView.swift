import SwiftUI
import SwiftData

/// 作文タブのトップ。書き溜めた英作文（Composition）を新しい順に一覧する。
/// FAB で新規作成、行タップで詳細（本文編集・添削）へ。
struct CompositionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Composition.updatedAt, order: .reverse) private var compositions: [Composition]

    @State private var newComposition: Composition?

    var body: some View {
        NavigationStack {
            Group {
                if compositions.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(compositions) { composition in
                            NavigationLink {
                                CompositionDetailView(composition: composition)
                            } label: {
                                CompositionRow(composition: composition)
                            }
                        }
                        .onDelete(perform: deleteCompositions)
                    }
                }
            }
            .navigationTitle("Writing")
            .wordTapRegistration()
            .overlay(alignment: .bottomTrailing) {
                if !compositions.isEmpty {
                    addFloatingButton
                }
            }
            // 新規作成: 空の Composition を作って詳細へ遷移し、そこで本文を書いて添削する
            .navigationDestination(item: $newComposition) { composition in
                CompositionDetailView(composition: composition, isNew: true)
            }
        }
    }

    /// 現在の母語設定で空の作文を作り、挿入して詳細へ遷移する
    private func startNewComposition() {
        let language = UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode)
            ?? AppSettingsKeys.defaultTargetLanguageCode
        let composition = Composition(explanationLanguage: language)
        modelContext.insert(composition)
        modelContext.saveOrLog()
        newComposition = composition
    }

    private func deleteCompositions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(compositions[index])
        }
        modelContext.saveOrLog()
    }

    private var addFloatingButton: some View {
        Button {
            startNewComposition()
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .accessibilityLabel("New Composition")
        .accessibilityIdentifier("compositionAddButton")
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            TappableEnglishText(text: "No Writing Yet")
                .font(.title2)
                .fontWeight(.semibold)
            TappableEnglishText(text: "Write in English and get AI feedback on your composition.", color: .secondary)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                startNewComposition()
            } label: {
                Label("New Composition", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("compositionAddButton")
        }
    }
}

struct CompositionRow: View {
    let composition: Composition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(composition.previewText.isEmpty ? "New Composition" : composition.previewText)
                .font(.headline)
                .lineLimit(2)
                .foregroundStyle(composition.previewText.isEmpty ? .secondary : .primary)
            HStack(spacing: 8) {
                Text(composition.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                statusBadge
            }
        }
        .padding(.vertical, 2)
    }

    /// 添削の状態バッジ。未添削 / 編集中（未送信の変更あり）/ 添削済み（ラウンド数）を出し分ける。
    @ViewBuilder
    private var statusBadge: some View {
        if !composition.hasFeedback {
            badge(text: "Not reviewed", color: .secondary)
        } else if !composition.draftMatchesLastRound {
            badge(text: "Editing", color: .orange)
        } else {
            let count = composition.rounds.count
            badge(text: count > 1 ? "Reviewed ×\(count)" : "Reviewed", color: .green)
        }
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

#Preview {
    CompositionsView()
        .modelContainer(for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self, AudioClip.self, YouTubeLink.self], inMemory: true)
}
