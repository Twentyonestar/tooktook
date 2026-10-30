#if DEBUG
import Foundation
import SwiftData

/// App Store 스크린샷용 예시 데이터. DEBUG 빌드에서 `-TookTookDemo` 인자로 실행할 때만 넣는다.
/// 배포(Release) 빌드에는 이 파일이 컴파일되지 않는다. 기록이 이미 있는 저장소에는 아무것도 하지 않는다.
@MainActor
enum DemoData {
    static let launchArgument = "-TookTookDemo"

    static func installIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: PrefKey.hasCompletedOnboarding)
        defaults.set(true, forKey: PrefKey.reminderEnabled)
        defaults.set(22 * 60, forKey: PrefKey.reminderMinutes)

        guard let container = StoreController.shared.container else { return }
        let context = container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Stack>())) ?? 0) == 0 else { return }
        let store = StackStore(context: context)
        store.seedDefaultCategoriesIfNeeded()
        try? populate(context)
    }

    private static let places = [
        "서울특별시 성동구 성수동2가", "서울특별시 마포구 연남동", "서울특별시 강남구 역삼동",
        "서울특별시 중구 명동", "서울특별시 종로구 삼청동", "서울특별시 용산구 한남동",
    ]

    private static func populate(_ context: ModelContext) throws {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        func id(_ key: String) -> UUID { DefaultCategory.forKey(key)!.fixedID }

        // 이번 달 확정 지출 (오늘 전까지)
        let spends: [(day: Int, hour: Int, minute: Int, key: String, amount: Int64, memo: String?)] = [
            (1, 12, 20, "food", 9_500, "점심"), (1, 8, 40, "cafe", 4_800, nil), (2, 19, 10, "food", 23_000, "저녁 약속"),
            (3, 8, 5, "transport", 1_500, nil), (4, 13, 0, "shopping", 39_000, "운동화 끈"), (5, 12, 30, "food", 11_000, nil),
            (6, 15, 20, "cafe", 6_300, nil), (7, 20, 0, "culture", 15_000, "영화"), (8, 12, 10, "food", 8_900, nil),
            (9, 18, 30, "living", 27_400, "생활용품"), (10, 8, 30, "transport", 1_500, nil), (11, 12, 45, "food", 10_500, nil),
            (12, 16, 0, "cafe", 5_500, nil), (13, 11, 20, "medical", 12_000, "약국"), (14, 12, 0, "food", 9_000, nil),
            (15, 19, 40, "food", 31_000, "회식 2차"), (16, 8, 50, "cafe", 4_500, nil), (17, 21, 0, "shopping", 18_900, nil),
            (18, 12, 15, "food", 9_800, nil), (19, 14, 30, "culture", 22_000, "전시"), (20, 8, 10, "transport", 3_000, nil),
            (21, 12, 25, "food", 12_000, nil), (22, 15, 45, "cafe", 6_800, nil), (23, 18, 20, "living", 14_500, nil),
            (24, 12, 40, "food", 8_500, nil), (25, 10, 0, "other", 20_000, "경조사"), (26, 19, 30, "food", 26_000, nil),
            (27, 8, 35, "cafe", 4_800, nil), (28, 12, 5, "food", 9_900, nil), (29, 17, 10, "shopping", 45_000, "셔츠"),
        ]
        let month = calendar.dateComponents([.year, .month], from: now)
        for (index, spend) in spends.enumerated() {
            guard let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: spend.day,
                                                                hour: spend.hour, minute: spend.minute)),
                  date < today
            else { continue }
            let stack = Stack(createdAt: date, captureSource: .appIntent, status: .completed, locationStatus: .captured)
            stack.placeLabel = places[index % places.count]
            stack.placeLabelVersion = PlaceLabelFormatter.version
            stack.latitude = 37.5
            stack.longitude = 127.0
            stack.horizontalAccuracy = 12
            let transaction = LedgerTransaction(sourceStackId: stack.id, amountKRW: spend.amount, categoryId: id(spend.key),
                                                occurredAt: date, memo: spend.memo)
            stack.transactionId = transaction.id
            stack.completedAt = date.addingTimeInterval(600)
            context.insert(stack)
            context.insert(transaction)
        }

        // 오늘: 정리 대기 3개 + 정리 완료 1개
        let pending: [(hour: Int, minute: Int, place: String)] = [
            (8, 12, "서울특별시 성동구 성수동2가"), (8, 47, "서울특별시 성동구 성수동1가"), (9, 20, "서울특별시 광진구 화양동"),
        ]
        for item in pending {
            let date = calendar.date(bySettingHour: item.hour, minute: item.minute, second: 0, of: today)!
            let stack = Stack(createdAt: date, captureSource: .appIntent, locationStatus: .captured)
            stack.placeLabel = item.place
            stack.placeLabelVersion = PlaceLabelFormatter.version
            stack.latitude = 37.54
            stack.longitude = 127.05
            stack.horizontalAccuracy = 10
            context.insert(stack)
        }
        let breakfast = calendar.date(bySettingHour: 7, minute: 55, second: 0, of: today)!
        let done = Stack(createdAt: breakfast, captureSource: .appIntent, status: .completed, locationStatus: .captured)
        done.placeLabel = "서울특별시 성동구 성수동2가"
        done.placeLabelVersion = PlaceLabelFormatter.version
        let doneSpend = LedgerTransaction(sourceStackId: done.id, amountKRW: 4_500, categoryId: id("cafe"), occurredAt: breakfast, memo: "아이스 아메리카노")
        done.transactionId = doneSpend.id
        done.completedAt = breakfast.addingTimeInterval(600)
        context.insert(done)
        context.insert(doneSpend)
        try context.save()
    }
}
#endif
