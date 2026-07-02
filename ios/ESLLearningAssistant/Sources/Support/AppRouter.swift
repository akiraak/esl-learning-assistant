import SwiftUI

enum AppTab: Hashable {
    case lessons
    case words
    case settings
}

/// タブ間の画面遷移を仲介するルーター。
/// レッスンタブの単語タップ → 単語タブへ切り替えて詳細表示、のようなタブ横断の遷移に使う。
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .lessons

    /// 単語タブで表示すべき単語。単語タブ側が表示したらクリアする。
    var pendingWord: Word?

    /// 単語タブで開くべき単語追加画面のレッスン（変更不可で固定）。単語タブ側が表示したらクリアする。
    var pendingAddWordLesson: Lesson?

    /// 単語タブへ切り替えて指定の単語の詳細を表示する
    func showWord(_ word: Word) {
        pendingWord = word
        selectedTab = .words
    }

    /// 単語タブへ切り替えて、レッスンを固定した状態で単語追加画面を開く
    func showAddWord(for lesson: Lesson) {
        pendingAddWordLesson = lesson
        selectedTab = .words
    }
}
