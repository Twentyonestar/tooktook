import Foundation
import SwiftData

/// 앱 코드는 별칭으로 현재 스키마 버전의 모델을 쓴다. 새 버전을 추가하면 별칭을 옮긴다.
typealias LedgerTransaction = SchemaV1.LedgerTransaction

extension SchemaV1 {
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
}
