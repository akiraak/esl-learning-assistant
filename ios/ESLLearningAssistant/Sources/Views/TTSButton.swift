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
        /// true でサーバ側キャッシュを破棄して合成し直す（「作り直す」用）。通常は省略。
        var regenerate: Bool? = nil
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
            // 長押し: 端末の古いローカル音声を捨ててサーバから取り直す。
            // 管理画面で音声を作り直した後、この端末のキャッシュを更新するために使う。
            .contextMenu {
                Button {
                    regenerate(current: localURL)
                } label: {
                    Label("AI音声を作り直す", systemImage: "arrow.clockwise")
                }
            }
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

    /// サーバで合成（保存済みならサーバキャッシュ返却）した音声を端末ローカルに保存する。
    /// regenerate=true のときはサーバに再合成させる（「作り直す」用）。
    private func generate(regenerate: Bool = false) {
        guard !isGenerating else { return }
        isGenerating = true
        // @State への書き込みを MainActor 上で行う（外すとメインスレッド外更新になり再描画されないことがある）
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let data = try await BackendAPI.post(
                    path: "api/tts",
                    body: RequestBody(text: text, model: serverModel, regenerate: regenerate ? true : nil)
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

    /// この単語の音声を作り直す。再生中なら止め、端末ローカルを削除したうえで、
    /// サーバにも再合成させて（regenerate=true）取り直し保存する。
    /// 単なる再取得だとサーバキャッシュの古い音声が返るため、必ずサーバ再合成を伴わせる。
    private func regenerate(current: URL) {
        guard !isGenerating else { return }
        if playback.currentURL == current {
            playback.stop()
        }
        TTSAudioStore.remove(text: text, model: serverModel)
        generate(regenerate: true)
    }
}
