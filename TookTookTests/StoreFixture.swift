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
}
