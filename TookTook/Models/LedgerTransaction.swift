import Foundation
import SwiftData

/// PRD의 Transaction. SwiftUI의 `Transaction`과 이름이 겹치지 않도록 LedgerTransaction으로 둔다.
@Model
final class LedgerTransaction {
    @Attribute(.unique) var id: UUID
    var sourceStackId: UUID?
    var amountKRW: Int64
    var categoryId: UUID
    var occurredAt: Date
    var memo: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sourceStackId: UUID?,
        amountKRW: Int64,
        categoryId: UUID,
        occurredAt: Date,
        memo: String?,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sourceStackId = sourceStackId
        self.amountKRW = amountKRW
        self.categoryId = categoryId
        self.occurredAt = occurredAt
        self.memo = memo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
