import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKeys.backendBaseURL)
    private var backendBaseURL = AppSettingsKeys.defaultBackendBaseURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("サーバーURL", text: $backendBaseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("バックエンド")
                } footer: {
                    Text(
                        "OCR・翻訳を処理するローカルバックエンドのURL。既定値は "
                            + AppSettingsKeys.defaultBackendBaseURL
                            + "（実機ビルドはrun-ios-device.shがMacのIPを自動設定）です。"
                            + "Macと異なるネットワークにいる場合などはここで変更してください。"
                    )
                }

                Section {
                    Text("日本語（固定）")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("翻訳先の母語")
                } footer: {
                    Text("母語を選択できる設定は今後実装予定です。")
                }
            }
            .navigationTitle("設定")
        }
    }
}

#Preview {
    SettingsView()
}
