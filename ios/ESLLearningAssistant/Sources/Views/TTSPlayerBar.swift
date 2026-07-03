import SwiftUI

/// 生成音声の操作パネル。ホスト画面の `.safeAreaInset(edge: .bottom)` に置き、
/// 再生中だけ画面下部に現れる（コンテンツを隠さず下に挿入されるので画面を見ながら聞ける）。
/// 一時停止・±5秒スキップ・シークバー・再生速度・閉じる（停止）を提供する。
struct TTSPlayerBar: View {
    @ObservedObject var playback: TTSPlaybackService

    /// シークバードラッグ中はタイマー更新でツマミが暴れないよう、ドラッグ位置を優先表示する
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    private static let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(Self.timeText(isScrubbing ? scrubTime : playback.currentTime))
                    .monospacedDigit()
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubTime : playback.currentTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(playback.duration, 0.01)
                ) { editing in
                    isScrubbing = editing
                    if !editing {
                        playback.seek(to: scrubTime)
                    }
                }
                Text(Self.timeText(playback.duration))
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                rateMenu
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 28) {
                    Button {
                        playback.skip(by: -5)
                    } label: {
                        Image(systemName: "gobackward.5")
                    }
                    .accessibilityLabel("Back 5 Seconds")

                    Button {
                        playback.togglePlayPause()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            // pause/playでアイコン幅が変わり両隣がズレるため幅を固定する
                            .frame(width: 28)
                    }
                    .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

                    Button {
                        playback.skip(by: 5)
                    } label: {
                        Image(systemName: "goforward.5")
                    }
                    .accessibilityLabel("Forward 5 Seconds")
                }

                Button {
                    playback.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close Player")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var rateMenu: some View {
        Menu {
            ForEach(Self.rates, id: \.self) { rate in
                Button {
                    playback.setRate(rate)
                } label: {
                    if rate == playback.rate {
                        Label(Self.rateText(rate), systemImage: "checkmark")
                    } else {
                        Text(Self.rateText(rate))
                    }
                }
            }
        } label: {
            Text(Self.rateText(playback.rate))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .accessibilityLabel("Playback Speed")
    }

    static func timeText(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func rateText(_ rate: Float) -> String {
        // 0.5× / 0.75× / 1× のように末尾の0を省いて短く表示する
        let text = String(format: "%g", rate)
        return "\(text)×"
    }
}
