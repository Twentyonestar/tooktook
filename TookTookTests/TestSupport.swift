import SwiftData
@testable import TookTook

/// 테스트마다 새 인메모리 저장소. 컨테이너가 해제되지 않도록 함께 들고 다닌다.
@MainActor
struct TestStore {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let schema = Schema([Stack.self, LedgerTransaction.self, ExpenseCategory.self])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    var store: StackStore { StackStore(context: context) }

    func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }
}
