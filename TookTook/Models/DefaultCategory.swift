import Foundation
import SwiftData

/// 기본 카테고리 8개의 기기 공통 정의.
/// 새 설치는 고정 UUID로 만들어서 여러 기기에서 같은 레코드가 된다.
/// SchemaV2 이전 설치본은 기존 UUID를 그대로 두고 defaultKey로만 표시한다(거래 참조 보존).
struct DefaultCategory: Equatable {
    let key: String
    let name: String
    let symbol: String
    /// 새 설치에서 쓰는 고정 ID. 한 번 배포하면 바꾸지 않는다.
    let fixedID: UUID

    static let all: [DefaultCategory] = [
        .init(key: "food", name: "식비", symbol: "fork.knife", fixedID: UUID(uuidString: "7D7D0000-0000-4000-8000-000000000001")!),
        .init(key: "cafe", name: "카페", symbol: "cup.and.saucer.fill", fixedID: UUID(uuidString: "7D7D0000-0000-4000-8000-000000000002")!),
        .init(key: "transport", name: "교통", symbol: "bus.fill", fixedID: UUID(uuidString: "7D7D0000-0000-4000-8000-000000000003")!),
        .init(key: "shopping", name: "쇼핑", symbol: "bag.fill", fixedID: UUID(uuidString: "7D7D0000-0000-4000-8000-000000000004")!),
        .init(key: "living", name: "생활", symbol: "house.fill", fixedID: UUID(uuidString: "7D7D0000-0000-4000-8000-000000000005")!),
        .init(key: "culture", name: "문화", symbol: "ticket.fill", fixedID: UUID(uuidString: "7D7D0000-0000-4000-8000-000000000006")!),
        .init(key: "medical", name: "의료", symbol: "cross.case.fill", fixedID: UUID(uuidString: "7D7D0000-0000-4000-8000-000000000007")!),
        .init(key: "other", name: "기타", symbol: "ellipsis.circle.fill", fixedID: UUID(uuidString: "7D7D0000-0000-4000-8000-000000000008")!),
    ]

    static func forKey(_ key: String) -> DefaultCategory? {
        all.first { $0.key == key }
    }

    /// SchemaV2 이전에 만들어진 카테고리 중 기본 시드로 만든 것에 defaultKey를 붙인다.
    /// 시드와 이름·아이콘·순서가 모두 같고 후보가 하나뿐일 때만 붙인다.
    /// 이름을 바꾼 기본 카테고리, 사용자가 만든 같은 이름 카테고리는 건드리지 않는다(잘못 합치는 것보다 안전).
    /// 이미 defaultKey가 있는 레코드는 그대로 둔다. ID·이름·보관 상태는 바꾸지 않는다.
    static func tagSeededDefaults(in categories: [ExpenseCategory]) {
        for (order, definition) in all.enumerated() {
            guard !categories.contains(where: { $0.defaultKey == definition.key }) else { continue }
            let candidates = categories.filter {
                $0.defaultKey == nil && $0.name == definition.name && $0.symbol == definition.symbol && $0.displayOrder == order
            }
            if candidates.count == 1 {
                candidates[0].defaultKey = definition.key
            }
        }
    }

    /// V1→V2 단계의 후처리가 실패한 뒤 다시 열린 저장소처럼, 기본 카테고리 표시가 하나도 없을 때만 같은 규칙으로 표시한다.
    /// 표시가 하나라도 있으면(정상 마이그레이션·새 설치) 아무것도 하지 않는다.
    @MainActor
    static func tagIfNeverTagged(in context: ModelContext) {
        guard let categories = try? context.fetch(FetchDescriptor<ExpenseCategory>()),
              !categories.isEmpty,
              !categories.contains(where: { $0.defaultKey != nil })
        else { return }
        tagSeededDefaults(in: categories)
        try? context.save()
    }
}
