import SwiftUI

// OCR/翻訳のバックグラウンド処理中に「動いている」ことを伝えるアニメーション部品群。
// レッスン画面（PhotoRow）とコンテンツ詳細画面（PhotoDetailView）で共有する。

/// opacity を呼吸のように上下させる pulse アニメーション修飾子。
private struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.45 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    /// 処理中テキストなどに穏やかな明滅を与える
    func pulse() -> some View { modifier(PulseModifier()) }
}

/// 横方向に光沢が流れるシマー付きのプレースホルダ行。詳細画面で結果テキストの代わりに見せる。
struct ShimmerSkeletonLine: View {
    /// 行幅の割合（0〜1）。段落らしく見せるため行ごとに変える
    var widthFraction: CGFloat = 1.0
    var height: CGFloat = 14

    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * widthFraction
            RoundedRectangle(cornerRadius: height / 2)
                .fill(Color.secondary.opacity(0.18))
                .frame(width: width, height: height)
                .overlay(
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.primary.opacity(0.18), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width, height: height)
                        .offset(x: phase * width * 1.4)
                        .mask(
                            RoundedRectangle(cornerRadius: height / 2)
                                .frame(width: width, height: height)
                        )
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
        .frame(height: height)
    }
}

/// コンテンツ詳細画面の「処理中」表示。スピナー + 明滅ラベル + シマーのスケルトン段落。
struct PhotoProcessingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ProgressView()
                TappableEnglishText(text: "Processing OCR & translation…", color: .secondary)
                    .foregroundStyle(.secondary)
                    .pulse()
            }
            VStack(alignment: .leading, spacing: 10) {
                ShimmerSkeletonLine(widthFraction: 0.92)
                ShimmerSkeletonLine(widthFraction: 0.78)
                ShimmerSkeletonLine(widthFraction: 0.64)
            }
        }
    }
}
