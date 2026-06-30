import SwiftUI
import SwiftData

struct ClassLessonSwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Class.createdAt) private var classes: [Class]

    @Binding var currentClassID: UUID?
    @Binding var currentLessonID: UUID?

    @State private var isShowingNewClassAlert = false
    @State private var newClassName = ""
    @State private var classAddingLesson: Class?
    @State private var newLessonTitle = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(classes) { schoolClass in
                    Section {
                        let lessons = schoolClass.lessons.sorted { $0.createdAt > $1.createdAt }
                        if lessons.isEmpty {
                            Text("レッスンがありません")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(lessons) { lesson in
                                Button {
                                    select(lesson: lesson, in: schoolClass)
                                } label: {
                                    HStack {
                                        Text(lesson.title)
                                        Spacer()
                                        if lesson.id == currentLessonID {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        HStack {
                            Text(schoolClass.name)
                            Spacer()
                            Button {
                                classAddingLesson = schoolClass
                                newLessonTitle = ""
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }

                Section {
                    Button {
                        newClassName = ""
                        isShowingNewClassAlert = true
                    } label: {
                        Label("クラスを追加", systemImage: "plus")
                    }
                    .accessibilityIdentifier("switcherAddClassButton")
                }
            }
            .navigationTitle("クラス・レッスン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("クラスを追加", isPresented: $isShowingNewClassAlert) {
                TextField("クラス名", text: $newClassName)
                Button("追加", action: addClass)
                Button("キャンセル", role: .cancel) {}
            }
            .alert(
                "レッスンを追加",
                isPresented: Binding(
                    get: { classAddingLesson != nil },
                    set: { isPresented in
                        if !isPresented { classAddingLesson = nil }
                    }
                )
            ) {
                TextField("レッスン名", text: $newLessonTitle)
                Button("追加", action: addLesson)
                Button("キャンセル", role: .cancel) { classAddingLesson = nil }
            }
        }
    }

    private func select(lesson: Lesson, in schoolClass: Class) {
        currentClassID = schoolClass.id
        currentLessonID = lesson.id
        dismiss()
    }

    private func addClass() {
        let trimmed = newClassName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newClass = Class(name: trimmed)
        modelContext.insert(newClass)
        currentClassID = newClass.id
        currentLessonID = nil
    }

    private func addLesson() {
        guard let schoolClass = classAddingLesson else { return }
        let trimmed = newLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            classAddingLesson = nil
            return
        }
        let lesson = Lesson(schoolClass: schoolClass, title: trimmed)
        modelContext.insert(lesson)
        currentClassID = schoolClass.id
        currentLessonID = lesson.id
        classAddingLesson = nil
    }
}
