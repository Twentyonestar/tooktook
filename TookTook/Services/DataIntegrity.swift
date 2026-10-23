import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.twentyonestar.tooktook", category: "DataIntegrity")

/// SchemaV2에서 unique 제약이 없어졌으므로 새 레코드 ID가 겹치지 않게 앱이 확인한다.
/// 같은 컨텍스트·메인 액터에서 '있는지 보고 만든다'일 뿐이며 SwiftData unique 같은 원자성은 없다.
/// 다른 기기(동기화)·다른 프로세스에서 같은 ID가 들어오는 경우는 DuplicateIDResolver가 사후에 다룬다.
@MainActor
enum UniqueID {
    static func newStackID(in context: ModelContext) -> UUID {
        make { id in (try? context.fetchCount(FetchDescriptor<Stack>(predicate: #Predicate { $0.id == id }))) ?? 0 > 0 }
    }

    static func newTransactionID(in context: ModelContext) -> UUID {
        make { id in (try? context.fetchCount(FetchDescriptor<LedgerTransaction>(predicate: #Predicate { $0.id == id }))) ?? 0 > 0 }
    }

    static func newCategoryID(in context: ModelContext) -> UUID {
        make { id in (try? context.fetchCount(FetchDescriptor<ExpenseCategory>(predicate: #Predicate { $0.id == id }))) ?? 0 > 0 }
    }

    /// 랜덤 UUID가 이미 있으면 다시 뽑는다. 기존 레코드를 덮어쓰지 않는다.
    static func make(isTaken: (UUID) -> Bool) -> UUID {
        var candidate = UUID()
        while isTaken(candidate) {
            logger.error("UUID collision on create; regenerating")
            candidate = UUID()
        }
        return candidate
    }
}

/// 같은 ID를 가진 레코드가 둘 이상일 때의 처리.
/// - 모든 값이 같은 사본: 하나만 남긴다(잃는 정보 없음).
/// - 값이 다른 레코드: 아무것도 지우거나 덮어쓰지 않고 보고만 한다.
@MainActor
enum DuplicateIDResolver {
    struct Report: Equatable {
        var removedIdenticalCopies = 0
        /// 모델 이름별, 값이 달라 그대로 둔 ID
        var conflictingIDs: [String: Set<UUID>] = [:]

        var isClean: Bool { removedIdenticalCopies == 0 && conflictingIDs.isEmpty }
    }

    @discardableResult
    static func resolve(in context: ModelContext) throws -> Report {
        var report = Report()
        try resolve(Stack.self, name: "Stack", in: context, report: &report) { stack in
            [stack.createdAt.timeIntervalSinceReferenceDate.description, stack.captureSourceRaw, stack.statusRaw,
             stack.latitude?.description, stack.longitude?.description, stack.horizontalAccuracy?.description,
             stack.locationStatusRaw, stack.placeLabel, stack.completedAt?.timeIntervalSinceReferenceDate.description,
             stack.transactionId?.uuidString, stack.discardedAt?.timeIntervalSinceReferenceDate.description,
             stack.isPossibleDuplicate.description, stack.placeLookupAttempts.description, stack.placeLabelVersion.description]
        }
        try resolve(LedgerTransaction.self, name: "LedgerTransaction", in: context, report: &report) { transaction in
            [transaction.sourceStackId?.uuidString, transaction.amountKRW.description, transaction.categoryId.uuidString,
             transaction.occurredAt.timeIntervalSinceReferenceDate.description, transaction.memo,
             transaction.createdAt.timeIntervalSinceReferenceDate.description, transaction.updatedAt.timeIntervalSinceReferenceDate.description]
        }
        try resolve(ExpenseCategory.self, name: "ExpenseCategory", in: context, report: &report) { category in
            [category.name, category.symbol, category.displayOrder.description, category.isArchived.description, category.defaultKey]
        }
        if report.removedIdenticalCopies > 0 {
            try context.save()
        }
        if !report.conflictingIDs.isEmpty {
            logger.error("Records share an ID but differ; left untouched: \(report.conflictingIDs.mapValues(\.count).description, privacy: .public)")
        }
        return report
    }

    private static func resolve<T: PersistentModel>(
        _ type: T.Type,
        name: String,
        in context: ModelContext,
        report: inout Report,
        fingerprint: (T) -> [String?]
    ) throws where T: Identifiable, T.ID == UUID {
        let groups = Dictionary(grouping: try context.fetch(FetchDescriptor<T>()), by: \.id).filter { $0.value.count > 1 }
        for (id, records) in groups {
            let prints = records.map { fingerprint($0).map { $0 ?? "∅" }.joined(separator: "|") }
            if Set(prints).count == 1 {
                for extra in records.dropFirst() {
                    context.delete(extra)
                    report.removedIdenticalCopies += 1
                }
            } else {
                report.conflictingIDs[name, default: []].insert(id)
            }
        }
    }
}

/// 같은 defaultKey를 가진 기본 카테고리가 여러 개일 때(여러 기기 동기화 후 예상) 하나로 모은다.
/// 대표: 고정 UUID인 것 → 거래가 가장 많은 것 → UUID 문자열이 작은 것.
/// 나머지는 지우지 않고 보관 처리하며, 그쪽 거래의 categoryId만 대표로 옮긴다. 이름·아이콘은 대표 것을 쓴다.
/// 사용자가 만든 카테고리(defaultKey nil)는 이름이 같아도 대상이 아니다.
@MainActor
enum DefaultCategoryMerger {
    @discardableResult
    static func mergeDuplicates(in context: ModelContext) throws -> Int {
        let categories = try context.fetch(FetchDescriptor<ExpenseCategory>())
        let groups = Dictionary(grouping: categories.filter { $0.defaultKey != nil }, by: { $0.defaultKey! })
            .filter { $0.value.count > 1 }
        guard !groups.isEmpty else { return 0 }

        let transactions = try context.fetch(FetchDescriptor<LedgerTransaction>())
        var merged = 0
        for (key, members) in groups {
            let usage = Dictionary(grouping: transactions, by: \.categoryId).mapValues(\.count)
            let fixedID = DefaultCategory.forKey(key)?.fixedID
            let canonical = members.sorted {
                if ($0.id == fixedID) != ($1.id == fixedID) { return $0.id == fixedID }
                let a = usage[$0.id] ?? 0, b = usage[$1.id] ?? 0
                if a != b { return a > b }
                return $0.id.uuidString < $1.id.uuidString
            }[0]

            let anyActive = members.contains { !$0.isArchived }
            for duplicate in members where duplicate !== canonical {
                for transaction in transactions where transaction.categoryId == duplicate.id {
                    transaction.categoryId = canonical.id
                }
                duplicate.isArchived = true
                duplicate.defaultKey = nil
                merged += 1
            }
            if anyActive { canonical.isArchived = false }
        }
        try context.save()
        logger.info("Merged \(merged) duplicate default categories")
        return merged
    }
}
