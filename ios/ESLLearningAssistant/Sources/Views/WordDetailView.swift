import SwiftUI
import SwiftData

struct WordDetailView: View {
    let word: Word

    var body: some View {
        List {
            Section("訳語") {
                Text(word.translation)
            }

            if let example = word.exampleSentence, !example.isEmpty {
                Section("例文") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(example)
                        if let source = word.exampleSentenceSource {
                            Text(source == .textbook ? "教科書より" : "AI生成")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if word.partOfSpeech != nil || word.grammarNote != nil {
                Section("品詞・文法") {
                    if let partOfSpeech = word.partOfSpeech {
                        LabeledContent("品詞", value: partOfSpeech)
                    }
                    if let grammarNote = word.grammarNote {
                        LabeledContent("文法", value: grammarNote)
                    }
                }
            }

            Section("登場したレッスン") {
                let occurrences = word.occurrences.sorted { $0.occurredAt > $1.occurredAt }
                if occurrences.isEmpty {
                    Text("レッスンとの関連付けはありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(occurrences) { occurrence in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(occurrence.lesson.title)
                                Text(occurrence.lesson.schoolClass.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(occurrence.occurredAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("登録情報") {
                LabeledContent("登録日") {
                    Text(word.registeredAt, style: .date)
                }
                LabeledContent("復習回数", value: "\(word.reviewState.reviewCount)回")
            }
        }
        .navigationTitle(word.text)
    }
}
