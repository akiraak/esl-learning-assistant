import SwiftUI
import SwiftData

struct ClassLessonSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Class.createdAt) private var classes: [Class]

    @Binding var currentClassID: UUID?
    @Binding var currentLessonID: UUID?

    @State private var isAddingClass = false
    @State private var classAddingLesson: Class?
    @State private var editingClass: Class?
    @State private var editingLesson: Lesson?

    var body: some View {
        NavigationStack {
            List {
                ForEach(classes) { schoolClass in
                    Section {
                        let lessons = schoolClass.lessons.sorted { $0.createdAt > $1.createdAt }
                        if lessons.isEmpty {
                            Text("No lessons yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(lessons) { lesson in
                                HStack {
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
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        editingLesson = lesson
                                    } label: {
                                        Image(systemName: "pencil.circle")
                                            .foregroundStyle(.tint)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("switcherEditLessonButton")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(schoolClass.name)
                            Spacer()
                            Button {
                                editingClass = schoolClass
                            } label: {
                                Image(systemName: "pencil.circle")
                            }
                            .accessibilityIdentifier("switcherEditClassButton")
                            Button {
                                classAddingLesson = schoolClass
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .accessibilityIdentifier("switcherAddLessonButton")
                        }
                    }
                }

                Section {
                    Button {
                        isAddingClass = true
                    } label: {
                        Label("Add Class", systemImage: "plus")
                    }
                    .accessibilityIdentifier("switcherAddClassButton")
                }
            }
            .navigationTitle("Classes & Lessons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $isAddingClass) {
                ClassAddView(
                    currentClassID: $currentClassID,
                    currentLessonID: $currentLessonID
                )
            }
            .navigationDestination(item: $classAddingLesson) { schoolClass in
                LessonAddView(
                    schoolClass: schoolClass,
                    currentClassID: $currentClassID,
                    currentLessonID: $currentLessonID
                ) {
                    // 作成したレッスンをすぐ使えるよう、シートごと閉じてレッスン画面へ戻る
                    dismiss()
                }
            }
            .navigationDestination(item: $editingClass) { schoolClass in
                ClassEditView(schoolClass: schoolClass)
            }
            .navigationDestination(item: $editingLesson) { lesson in
                LessonEditView(lesson: lesson)
            }
        }
    }

    private func select(lesson: Lesson, in schoolClass: Class) {
        currentClassID = schoolClass.id
        currentLessonID = lesson.id
        dismiss()
    }
}
