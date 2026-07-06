import UIKit

/// 音声再生中に iPhone が自動ロック（スリープ）して再生が途切れないよう、
/// `isIdleTimerDisabled` を集約管理する。
///
/// このフラグはアプリ全体で共有される 1 つの状態のため、複数の再生サービスが
/// 個別に true/false を書き込むと、片方の停止でもう片方の再生中に自動ロックが
/// 復活してしまう。要求中の owner を集合で保持し、1 つでも要求があれば画面を
/// 消させない、すべて解放されたら元に戻す（冪等・要求のリークなし）。
@MainActor
enum ScreenWakeLock {
    private static var owners = Set<ObjectIdentifier>()

    /// - Parameters:
    ///   - active: この owner が画面を消させたくないなら true、解放するなら false
    ///   - owner: 要求元。同一 owner の重複要求は 1 つとして扱う
    static func setActive(_ active: Bool, owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        if active {
            owners.insert(id)
        } else {
            owners.remove(id)
        }
        UIApplication.shared.isIdleTimerDisabled = !owners.isEmpty
    }
}
