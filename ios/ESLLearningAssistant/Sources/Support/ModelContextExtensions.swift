import Foundation
import OSLog
import SwiftData

extension ModelContext {
    private static let saveLogger = Logger(
        subsystem: "com.akiraak.esllearningassistant",
        category: "SwiftData"
    )

    /// save() の失敗を握りつぶさず記録する。debug ビルドでは assertionFailure で即座に気付けるようにする
    func saveOrLog(function: String = #function) {
        do {
            try save()
        } catch {
            Self.saveLogger.error(
                "modelContext.save() failed in \(function, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            assertionFailure("modelContext.save() failed in \(function): \(error)")
        }
    }
}
