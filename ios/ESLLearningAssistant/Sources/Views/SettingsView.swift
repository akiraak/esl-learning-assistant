import SwiftData
import SwiftUI

#if DEBUG
private enum DebugDeleteAction: String, Identifiable {
    case allData
    case classes
    case words

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allData: "Delete All Data"
        case .classes: "Delete a Class and Its Lessons"
        case .words: "Delete All Words"
        }
    }

    var message: String {
        switch self {
        case .allData:
            "All classes, lessons, photos, and words will be deleted. This cannot be undone."
        case .classes:
            "Choose a class to delete. Its lessons and photos will also be deleted (words are kept). This cannot be undone."
        case .words:
            "All words will be deleted (classes, lessons, and photos are kept). This cannot be undone."
        }
    }
}
#endif

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.backendBaseURL)
    private var backendBaseURL = AppSettingsKeys.defaultBackendBaseURL
    @AppStorage(AppSettingsKeys.ttsEngine)
    private var ttsEngine = AppSettingsKeys.defaultTTSEngine
    @AppStorage(AppSettingsKeys.ttsVoice)
    private var ttsVoice = AppSettingsKeys.defaultTTSVoice
    @AppStorage(AppSettingsKeys.ttsModel)
    private var ttsModel = AppSettingsKeys.defaultTTSModel

    #if DEBUG
    @Environment(\.modelContext) private var modelContext
    @Query private var classes: [Class]
    @Query private var lessons: [Lesson]
    @Query private var photos: [Photo]
    @Query private var words: [Word]
    @State private var pendingDeleteAction: DebugDeleteAction?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $backendBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Backend")
                } footer: {
                    Text(
                        "URL of the local backend that handles OCR & translation. The default is "
                            + AppSettingsKeys.defaultBackendBaseURL
                            + " (device builds are set to your Mac's IP by run-ios-device.sh). "
                            + "Change this if you are on a different network from your Mac."
                    )
                }

                Section {
                    Text("Japanese (fixed)")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Native Language")
                } footer: {
                    Text("Language selection is coming soon.")
                }

                Section {
                    Picker("Speech Engine", selection: $ttsEngine) {
                        Text("On-Device").tag("local")
                        Text("Gemini").tag("gemini")
                    }
                    Picker("Voice", selection: $ttsVoice) {
                        Text("Chobi").tag("chobi")
                        Text("Naruko").tag("naruko")
                    }
                    .disabled(ttsEngine != "gemini")
                    Picker("TTS Model", selection: $ttsModel) {
                        Text("Fast").tag("flash")
                        Text("High Quality").tag("pro")
                    }
                    .disabled(ttsEngine != "gemini")
                } header: {
                    Text("Text-to-Speech")
                } footer: {
                    Text(
                        "Voice used to read the OCR result (English) aloud. On-Device plays "
                            + "instantly without network access; Gemini generates more natural "
                            + "speech via the backend (voice and model selectable). "
                            + "High Quality may take longer to generate."
                    )
                }

                #if DEBUG
                Section {
                    Button(DebugDeleteAction.allData.title, role: .destructive) {
                        pendingDeleteAction = .allData
                    }
                    Button(DebugDeleteAction.classes.title, role: .destructive) {
                        pendingDeleteAction = .classes
                    }
                    .disabled(classes.isEmpty)
                    Button(DebugDeleteAction.words.title, role: .destructive) {
                        pendingDeleteAction = .words
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text(
                        "Current data: \(classes.count) classes, \(lessons.count) lessons, "
                            + "\(photos.count) photos, \(words.count) words (Debug builds only)"
                    )
                }
                #endif
            }
            #if DEBUG
            .confirmationDialog(
                pendingDeleteAction?.title ?? "",
                isPresented: Binding(
                    get: { pendingDeleteAction != nil },
                    set: { if !$0 { pendingDeleteAction = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDeleteAction
            ) { action in
                if action == .classes {
                    ForEach(classes) { schoolClass in
                        Button(
                            "\(schoolClass.name) (\(schoolClass.lessons.count) lessons)",
                            role: .destructive
                        ) {
                            deleteClass(schoolClass)
                        }
                    }
                    Button("Delete All Classes", role: .destructive) {
                        perform(.classes)
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        perform(action)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text(action.message)
            }
            #endif
        }
    }

    #if DEBUG
    private func perform(_ action: DebugDeleteAction) {
        do {
            switch action {
            case .allData:
                try DebugDataCleaner.deleteAllData(context: modelContext)
            case .classes:
                try DebugDataCleaner.deleteAllClasses(context: modelContext)
            case .words:
                try DebugDataCleaner.deleteAllWords(context: modelContext)
            }
        } catch {
            print("DebugDataCleaner failed: \(error)")
        }
    }

    private func deleteClass(_ schoolClass: Class) {
        do {
            try DebugDataCleaner.deleteClass(schoolClass, context: modelContext)
        } catch {
            print("DebugDataCleaner failed: \(error)")
        }
    }
    #endif
}

#Preview {
    SettingsView()
        .modelContainer(
            for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self],
            inMemory: true
        )
}
