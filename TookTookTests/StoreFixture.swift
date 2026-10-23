import Foundation
import SwiftData
import Testing
@testable import TookTook

/// 마이그레이션 테스트용 저장소 픽스처의 고정 값.
/// 픽스처 파일(TookTookTests/Fixtures/StoreV0)은 VersionedSchema 도입 전 커밋 648696e의 모델로 만들었다.
/// 개인 정보가 없는 합성 데이터다.
enum StoreFixture {
    static let archivedCategoryID = UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!
    static let foodCategoryID = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!

    static let completedStackID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
    static let pendingStackID = UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!
    static let discardedStackID = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!
    static let retryingStackID = UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!
    static let archivedSpendStackID = UUID(uuidString: "A0000000-0000-0000-0000-000000000005")!

    static let foodTransactionID = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    static let archivedTransactionID = UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!

    static let baseDate = Date(timeIntervalSince1970: 1_798_000_000)

    /// 현재 모델로 픽스처 내용을 채운다. 생성기와 검증이 같은 값을 쓰도록 한곳에 둔다.
    @MainActor
    static func populate(_ context: ModelContext) throws {
        context.insert(ExpenseCategory(id: foodCategoryID, name: "식비", symbol: "fork.knife", displayOrder: 0))
        context.insert(ExpenseCategory(id: archivedCategoryID, name: "옛 카테고리", symbol: "tag", displayOrder: 1, isArchived: true))

        let completed = Stack(id: completedStackID, createdAt: baseDate, captureSource: .appIntent, status: .completed, locationStatus: .captured)
        completed.latitude = 37.5
        completed.longitude = 127.0
        completed.horizontalAccuracy = 12.5
        completed.placeLabel = "테스트시 테스트구 테스트동"
        completed.placeLabelVersion = 1
        completed.completedAt = baseDate.addingTimeInterval(600)
        completed.transactionId = foodTransactionID
        context.insert(completed)
        context.insert(LedgerTransaction(
            id: foodTransactionID, sourceStackId: completedStackID, amountKRW: 12_500, categoryId: foodCategoryID,
            occurredAt: baseDate.addingTimeInterval(-120), memo: "점심",
            createdAt: baseDate.addingTimeInterval(600), updatedAt: baseDate.addingTimeInterval(900)
        ))

        let pending = Stack(id: pendingStackID, createdAt: baseDate.addingTimeInterval(3_600), captureSource: .appIntent,
                            locationStatus: .unauthorized, isPossibleDuplicate: true)
        context.insert(pending)

        let discarded = Stack(id: discardedStackID, createdAt: baseDate.addingTimeInterval(7_200), captureSource: .inApp, status: .discarded,
                              locationStatus: .timedOut)
        discarded.discardedAt = baseDate.addingTimeInterval(7_300)
        context.insert(discarded)

        let retrying = Stack(id: retryingStackID, createdAt: baseDate.addingTimeInterval(10_800), captureSource: .appIntent, locationStatus: .captured)
        retrying.latitude = 35.1
        retrying.longitude = 129.0
        retrying.horizontalAccuracy = 30
        retrying.placeLookupAttempts = 2
        context.insert(retrying)

        let archivedSpend = Stack(id: archivedSpendStackID, createdAt: baseDate.addingTimeInterval(14_400), captureSource: .imported,
                                  status: .completed, locationStatus: .removed)
        archivedSpend.completedAt = baseDate.addingTimeInterval(14_500)
        archivedSpend.transactionId = archivedTransactionID
        context.insert(archivedSpend)
        context.insert(LedgerTransaction(
            id: archivedTransactionID, sourceStackId: archivedSpendStackID, amountKRW: 3_000, categoryId: archivedCategoryID,
            occurredAt: baseDate.addingTimeInterval(14_400), memo: nil,
            createdAt: baseDate.addingTimeInterval(14_500), updatedAt: baseDate.addingTimeInterval(14_500)
        ))
        try context.save()
    }
}

/// StoreV1 픽스처(커밋 1ca72b6, SchemaV1으로 기록)의 기본 카테고리 구성.
/// 앱의 첫 실행 시드와 같은 이름·아이콘·순서이며, 정리 정책을 검증할 변형을 섞었다.
enum StoreV1Fixture {
    /// 시드 순서대로의 기본 카테고리 ID (식비, 카페, 교통, 쇼핑, 생활, 문화, 의료, 기타)
    static let defaultIDs: [UUID] = (1...8).map { UUID(uuidString: String(format: "D0000000-0000-0000-0000-%012d", $0))! }
    /// 사용자가 이름을 "커피"로 바꾼 기본 카테고리(원래 카페)
    static var renamedCafeID: UUID { defaultIDs[1] }
    /// 사용자가 보관한 기본 카테고리(의료)
    static var archivedMedicalID: UUID { defaultIDs[6] }
    /// 사용자가 직접 만든 "식비"(기본 카테고리와 이름·아이콘이 같지만 순서가 다름)
    static let userFoodID = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!
    /// 사용자가 직접 만든 "술자리"
    static let userDrinksID = UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!

    static let transactionIDs: [UUID] = (1...4).map { UUID(uuidString: String(format: "F0000000-0000-0000-0000-%012d", $0))! }
    static let stackIDs: [UUID] = (1...5).map { UUID(uuidString: String(format: "A1000000-0000-0000-0000-%012d", $0))! }
    static let baseDate = Date(timeIntervalSince1970: 1_799_000_000)

    @MainActor
    static func populate(_ context: ModelContext) throws {
        for (index, item) in ExpenseCategory.defaults.enumerated() {
            context.insert(ExpenseCategory(id: defaultIDs[index], name: item.name, symbol: item.symbol, displayOrder: index))
        }
        try context.save()
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        categories.first { $0.id == renamedCafeID }?.name = "커피"
        categories.first { $0.id == archivedMedicalID }?.isArchived = true
        context.insert(ExpenseCategory(id: userFoodID, name: "식비", symbol: "fork.knife", displayOrder: 8))
        context.insert(ExpenseCategory(id: userDrinksID, name: "술자리", symbol: "wineglass.fill", displayOrder: 9))

        // 카테고리마다 지출 하나씩: 기본 식비, 이름 바꾼 카페, 보관한 의료, 사용자 식비
        let targets = [defaultIDs[0], renamedCafeID, archivedMedicalID, userFoodID]
        for (index, categoryID) in targets.enumerated() {
            let stack = Stack(id: stackIDs[index], createdAt: baseDate.addingTimeInterval(Double(index) * 600),
                              captureSource: .appIntent, status: .completed, locationStatus: .captured)
            stack.latitude = 37.0 + Double(index) / 100
            stack.longitude = 127.0
            stack.horizontalAccuracy = 10
            stack.placeLabel = "테스트시 \(index)동"
            stack.placeLabelVersion = 1
            stack.completedAt = stack.createdAt.addingTimeInterval(60)
            stack.transactionId = transactionIDs[index]
            context.insert(stack)
            context.insert(LedgerTransaction(
                id: transactionIDs[index], sourceStackId: stack.id, amountKRW: Int64(1_000 * (index + 1)),
                categoryId: categoryID, occurredAt: stack.createdAt, memo: index == 0 ? "메모" : nil,
                createdAt: stack.completedAt!, updatedAt: stack.completedAt!
            ))
        }
        let pending = Stack(id: stackIDs[4], createdAt: baseDate.addingTimeInterval(5_000), captureSource: .appIntent,
                            locationStatus: .unauthorized, isPossibleDuplicate: true)
        context.insert(pending)
        try context.save()
    }
}

/// 픽스처 생성기. 평소에는 건너뛰고, TOOKTOOK_FIXTURE_DIR이 있을 때만 그 폴더에 저장소를 만든다.
/// xcodebuild test 실행 시 TEST_RUNNER_TOOKTOOK_FIXTURE_DIR=<폴더>로 넘긴다.
@MainActor
struct StoreFixtureGenerator {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOOKTOOK_FIXTURE_DIR"] != nil))
    func generateStoreFixture() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TOOKTOOK_FIXTURE_DIR"]!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("default.store")
        let schema = Schema([Stack.self, LedgerTransaction.self, ExpenseCategory.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        try StoreFixture.populate(ModelContext(container))
    }

    /// TOOKTOOK_FIXTURE_V1_DIR이 있을 때만 그 시점 앱 코드(Persistence.openContainer)로 storeV1.store를 만든다.
    /// 커밋 1ca72b6(SchemaV1)에서 한 번 실행해 TookTookTests/Fixtures/StoreV1에 저장했다.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOOKTOOK_FIXTURE_V1_DIR"] != nil))
    func generateStoreV1Fixture() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TOOKTOOK_FIXTURE_V1_DIR"]!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = try Persistence.openContainer(
            at: directory.appending(path: "storeV1.store"),
            backupsDirectory: FileManager.default.temporaryDirectory.appending(path: "fixture-backups-\(UUID().uuidString)"),
            defaults: UserDefaults(suiteName: "tooktook.fixture.\(UUID().uuidString)")!
        )
        try StoreV1Fixture.populate(ModelContext(container))
    }
}
