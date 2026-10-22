import SwiftData

/// 앱 UI와 App Intent가 같은 컨테이너를 쓰도록 하나만 만든다.
@MainActor
enum Persistence {
    static let container: ModelContainer = {
        let schema = Schema([Stack.self, LedgerTransaction.self, ExpenseCategory.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            fatalError("ModelContainer를 만들 수 없습니다: \(error)")
        }
    }()
}
