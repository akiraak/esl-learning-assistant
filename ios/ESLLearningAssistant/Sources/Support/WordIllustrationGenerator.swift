import Foundation

/// 単語イラストのバックグラウンド生成を担う共有インスタンス。
/// AI単語情報の生成完了後に自動で呼ばれるため、画面が閉じていても生成が走る。
/// 生成状態（生成中・失敗）を @Published で配信し、WordIllustrationRow が
/// スピナー → 画像差し替えの表示に使う。多重リクエストはキー単位で排他する。
@MainActor
final class WordIllustrationGenerator: ObservableObject {
    static let shared = WordIllustrationGenerator()

    /// 生成中のキー（WordIllustrationStore.key）
    @Published private(set) var inFlight: Set<String> = []
    /// 直近の失敗（キー → エラーメッセージ）。再実行が始まるとクリアされる
    @Published private(set) var failures: [String: String] = [:]

    private let service: WordIllustrationService

    init(service: WordIllustrationService = RemoteWordIllustrationService()) {
        self.service = service
    }

    func isGenerating(word: String, targetLanguage: String) -> Bool {
        inFlight.contains(WordIllustrationStore.key(word: word, targetLanguage: targetLanguage))
    }

    func failureMessage(word: String, targetLanguage: String) -> String? {
        failures[WordIllustrationStore.key(word: word, targetLanguage: targetLanguage)]
    }

    /// 端末ローカルに未保存かつ生成中でなければ、サーバ生成 → ローカル保存を開始してすぐ戻る。
    /// サーバに保存済みならサーバキャッシュが返るだけなので、二重呼び出しにも安全。
    func generateIfNeeded(word: String, targetLanguage: String) {
        let key = WordIllustrationStore.key(word: word, targetLanguage: targetLanguage)
        guard WordIllustrationStore.localURL(word: word, targetLanguage: targetLanguage) == nil,
              !inFlight.contains(key) else { return }
        inFlight.insert(key)
        failures[key] = nil
        Task {
            defer { inFlight.remove(key) }
            do {
                let data = try await service.fetchIllustration(
                    word: word, targetLanguage: targetLanguage, senseIndex: 0
                )
                try WordIllustrationStore.save(data: data, word: word, targetLanguage: targetLanguage)
            } catch {
                failures[key] = error.localizedDescription
            }
        }
    }
}
