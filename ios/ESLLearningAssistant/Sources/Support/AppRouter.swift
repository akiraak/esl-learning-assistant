import SwiftUI

enum AppTab: Hashable {
    case lessons
    case words
    case writing
    case audio
    case documents
    case settings
}

/// タブ選択を保持するルーター。
/// タブ横断の遷移が必要になった場合の仲介役もここに置く。
@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .lessons
}
