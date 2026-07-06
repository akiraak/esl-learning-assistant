import SwiftUI

/// サーバTTS（Gemini）の生成→再生ボタン。ttsModel が On-Device でも常にサーバTTSを使う専用ボタン。
/// 未生成（端末ローカルにファイルなし）なら生成ボタン、生成中はスピナー、
/// 生成済みなら再生/停止ボタンになる。生成した音声はサーバと端末ローカルの両方に保存され、
/// 2回目以降の生成はサーバキャッシュ、再訪時の再生は端末ローカルから行われる。
/// 単語詳細・写真コンテンツ詳細など、AI音声の生成/再生が要る画面で共有する。
struct TTSButton: View {
    let text: String
    @ObservedObject var playback: TTSPlaybackService
    @Binding var errorMessage: String?
    /// 生成失敗時の差し替えフック。指定時は errorMessage をセットせずこれを呼ぶ
    /// （写真側で端末内蔵TTSへフォールバックさせるために使う）。
    var onGenerateFailure: (() -> Void)? = nil

    @AppStorage(AppSettingsKeys.ttsModel) private var model = AppSettingsKeys.defaultTTSModel
    @State private var isGenerating = false

    /// ttsModel が "local"（On-Device）のときはサーバが受け付けるモデルに読み替える
    private var serverModel: String {
        model == "local" ? AppSettingsKeys.fallbackServerTTSModel : model
    }

    private struct RequestBody: Encodable {
        let text: String
        let model: String
    }

    var body: some View {
        // 存在チェックのみで軽量。model 設定を変えるとキーが変わり「未生成」に戻る
        let localURL = TTSAudioStore.localURL(text: text, model: serverModel)
        if isGenerating {
            ProgressView()
        } else if let localURL {
            // 一時停止中もこの行の音源がロードされたままなので、停止（アンロード）ボタンを出す
            let isActive = playback.currentURL == localURL
            Button {
                if isActive {
                    playback.stop()
                } else {
                    playback.play(url: localURL)
                }
            } label: {
                Image(systemName: isActive ? "stop.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isActive ? "Stop" : "Play AI Audio")
        } else {
            Button {
                generate()
            } label: {
                Image(systemName: "waveform.badge.plus")
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Generate AI Audio")
        }
    }

    /// サーバで合成（保存済みならサーバキャッシュ返却）した音声を端末ローカルに保存する
    private func generate() {
        guard !isGenerating else { return }
        isGenerating = true
        // @State への書き込みを MainActor 上で行う（外すとメインスレッド外更新になり再描画されないことがある）
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let data = try await BackendAPI.post(
                    path: "api/tts",
                    body: RequestBody(text: text, model: serverModel)
                )
                try TTSAudioStore.save(data: data, text: text, model: serverModel)
            } catch {
                // フォールバック指定があればそちらへ委譲、無ければ従来どおりアラート表示用に伝える
                if let onGenerateFailure {
                    onGenerateFailure()
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
