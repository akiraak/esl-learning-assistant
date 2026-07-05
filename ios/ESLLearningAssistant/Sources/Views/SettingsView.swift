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
    @AppStorage(AppSettingsKeys.apiSecret)
    private var apiSecret = AppSettingsKeys.defaultAPISecret
    @AppStorage(AppSettingsKeys.ttsModel)
    private var ttsModel = AppSettingsKeys.defaultTTSModel

    @State private var isTestingConnection = false
    @State private var connectionTestResult: BackendAPI.ConnectionTestResult?

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
                    TextField("API Secret", text: $apiSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button {
                        Task {
                            isTestingConnection = true
                            connectionTestResult = await BackendAPI.testConnection()
                            isTestingConnection = false
                        }
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTestingConnection)
                    if let result = connectionTestResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.serverLine)
                                .foregroundStyle(result.serverLine.hasPrefix("Server: OK") ? .green : .red)
                            Text(result.secretLine)
                                .foregroundStyle(result.secretLine.hasPrefix("API Secret: OK") ? .green : .red)
                        }
                        .font(.footnote.monospaced())
                    }
                } header: {
                    TappableEnglishText(text: "Backend")
                } footer: {
                    TappableEnglishText(
                        text: "URL of the backend that handles OCR & translation. The default is "
                            + AppSettingsKeys.defaultBackendBaseURL
                            + ". For local development, switch to http://localhost:8801 "
                            + "(run-ios-device.sh sets device builds to your Mac's IP). "
                            + "API Secret is required to call the backend; a wrong or empty "
                            + "value causes authentication (401) errors."
                    )
                }

                Section {
                    TappableEnglishText(text: "Japanese (fixed)", color: .secondary)
                        .foregroundStyle(.secondary)
                } header: {
                    TappableEnglishText(text: "Native Language")
                } footer: {
                    TappableEnglishText(text: "Language selection is coming soon.")
                }

                Section {
                    Picker("TTS Model", selection: $ttsModel) {
                        Text("On-Device").tag("local")
                        Text("Gemini 2.5 Flash TTS").tag("flash")
                        Text("Gemini 2.5 Pro TTS").tag("pro")
                    }
                } header: {
                    TappableEnglishText(text: "Text-to-Speech")
                } footer: {
                    TappableEnglishText(
                        text: "Model used to read the OCR result (English) aloud. On-Device plays "
                            + "instantly without network access. Gemini 2.5 Flash TTS is fast; "
                            + "Gemini 2.5 Pro TTS sounds more natural but may take longer to "
                            + "generate. The Gemini voice character is picked randomly for "
                            + "each generation."
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
                    TappableEnglishText(text: "Debug")
                } footer: {
                    TappableEnglishText(
                        text: "Current data: \(classes.count) classes, \(lessons.count) lessons, "
                            + "\(photos.count) photos, \(words.count) words (Debug builds only)"
                    )
                }
                #endif
            }
            // 設定画面の英語ラベル・見出し・説明文の単語タップ→登録/詳細遷移
            .wordTapRegistration()
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
            for: [Class.self, Lesson.self, Photo.self, Word.self, WordOccurrence.self, Composition.self, AudioClip.self],
            inMemory: true
        )
}
