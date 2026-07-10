import SwiftUI
import SwiftData

/// クラス/レッスンの切り替えシート。レッスンは「クラス内で1日1つ」なので、
/// 一覧ではなくクラスごとのカレンダーで選択・作成する（docs/plans/archive/lesson-calendar.md）。
/// レッスンのある日（ドット）をタップ → 選択して閉じる。空き日をタップ → 作成確認
/// （タイトルは任意）→ 作成・選択して閉じる。
struct ClassLessonSwitcherView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Class.createdAt) private var classes: [Class]

    @Binding var currentClassID: UUID?
    @Binding var currentLessonID: UUID?

    /// カレンダーに表示中のクラス。nil なら現在クラスに追従する（Menu で明示切り替え時のみ設定）
    @State private var displayedClassID: UUID?
    @State private var isAddingClass = false
    @State private var editingClass: Class?
    /// 空き日タップ → 作成確認アラートの対象日（nil なら非表示）
    @State private var pendingCreationDate: Date?
    @State private var newLessonTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if let schoolClass = displayedClass {
                    calendarContent(schoolClass)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Lessons")
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
            .navigationDestination(item: $editingClass) { schoolClass in
                ClassEditView(schoolClass: schoolClass)
            }
            // クラス追加・切り替えで現在クラスが変わったらカレンダーも追従させる
            .onChange(of: currentClassID) {
                displayedClassID = nil
            }
            .alert(
                "New Lesson",
                isPresented: creationAlertBinding,
                presenting: pendingCreationDate
            ) { date in
                TextField("Title (optional)", text: $newLessonTitle)
                    .accessibilityIdentifier("lessonTitleField")
                Button("Create") { createLesson(on: date) }
                Button("Cancel", role: .cancel) {}
            } message: { date in
                Text("Create a lesson on \(Self.dateText(date)) in \(displayedClass?.name ?? "")?")
            }
        }
    }

    // MARK: - 表示中クラス

    private var displayedClass: Class? {
        if let id = displayedClassID, let match = classes.first(where: { $0.id == id }) {
            return match
        }
        if let id = currentClassID, let match = classes.first(where: { $0.id == id }) {
            return match
        }
        return classes.max(by: { $0.createdAt < $1.createdAt })
    }

    // MARK: - カレンダー

    private func calendarContent(_ schoolClass: Class) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                classPickerBar(schoolClass)
                LessonCalendarView(
                    schoolClass: schoolClass,
                    currentLessonID: currentLessonID
                ) { date in
                    handleTap(on: date, in: schoolClass)
                }
                Button {
                    handleTap(on: .now, in: schoolClass)
                } label: {
                    Label(
                        schoolClass.lesson(on: .now) == nil ? "Create Today's Lesson" : "Open Today's Lesson",
                        systemImage: "calendar.badge.checkmark"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("calendarTodayLessonButton")
                Text("Tap a dotted day to open its lesson, or an empty day to create one.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func classPickerBar(_ schoolClass: Class) -> some View {
        HStack {
            Menu {
                ForEach(classes) { candidate in
                    Button {
                        displayedClassID = candidate.id
                    } label: {
                        if candidate.id == schoolClass.id {
                            Label(candidate.name, systemImage: "checkmark")
                        } else {
                            Text(candidate.name)
                        }
                    }
                }
                Divider()
                Button {
                    isAddingClass = true
                } label: {
                    Label("Add Class", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(schoolClass.name)
                        .font(.headline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("switcherClassMenuButton")

            Spacer()

            Button {
                editingClass = schoolClass
            } label: {
                Image(systemName: "pencil.circle")
            }
            .accessibilityIdentifier("switcherEditClassButton")
        }
    }

    // MARK: - 空状態

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Classes")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Add a class you are taking to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                isAddingClass = true
            } label: {
                Label("Add Class", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("switcherAddClassButton")
        }
    }

    // MARK: - アクション

    private var creationAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingCreationDate != nil },
            set: { if !$0 { pendingCreationDate = nil } }
        )
    }

    private func handleTap(on date: Date, in schoolClass: Class) {
        if let lesson = schoolClass.lesson(on: date) {
            select(lesson: lesson, in: schoolClass)
        } else {
            newLessonTitle = ""
            pendingCreationDate = date
        }
    }

    private func createLesson(on date: Date) {
        guard let schoolClass = displayedClass else { return }
        // 防御: 同日のレッスンができていたら作成せず選択に切り替える（クラス内で日付は一意）
        if let existing = schoolClass.lesson(on: date) {
            select(lesson: existing, in: schoolClass)
            return
        }
        let title = newLessonTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let lesson = Lesson(schoolClass: schoolClass, title: title, date: date)
        modelContext.insert(lesson)
        modelContext.saveOrLog()
        select(lesson: lesson, in: schoolClass)
    }

    private func select(lesson: Lesson, in schoolClass: Class) {
        currentClassID = schoolClass.id
        currentLessonID = lesson.id
        dismiss()
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated).weekday(.abbreviated))
    }
}
