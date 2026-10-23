import Foundation
import SwiftData

// 고정된 스키마. 버전 관리 이전 앱(648696e까지)과 SchemaV1 앱(1ca72b6까지)이 기록한 저장소와 같은 모양이어야 한다.
// 저장 속성, 기본값, unique를 바꾸지 말 것. 앱 동작 코드는 SchemaV2 모델에 있다.
// 검증: TookTookTests/Fixtures/StoreV0, StoreV1.

extension SchemaV1 {
    @Model
    final class Stack {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var captureSourceRaw: String
        var statusRaw: String
        var latitude: Double?
        var longitude: Double?
        var horizontalAccuracy: Double?
        var locationStatusRaw: String
        var placeLabel: String?
        var completedAt: Date?
        var transactionId: UUID?
        var discardedAt: Date?
        var isPossibleDuplicate: Bool
        var placeLookupAttempts: Int = 0
        var placeLabelVersion: Int = 0

        init(id: UUID, createdAt: Date, captureSourceRaw: String, statusRaw: String, locationStatusRaw: String, isPossibleDuplicate: Bool) {
            self.id = id
            self.createdAt = createdAt
            self.captureSourceRaw = captureSourceRaw
            self.statusRaw = statusRaw
            self.locationStatusRaw = locationStatusRaw
            self.isPossibleDuplicate = isPossibleDuplicate
        }
    }

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

        init(id: UUID, sourceStackId: UUID?, amountKRW: Int64, categoryId: UUID, occurredAt: Date, memo: String?, createdAt: Date, updatedAt: Date) {
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

    @Model
    final class ExpenseCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        var symbol: String
        var displayOrder: Int
        var isArchived: Bool

        init(id: UUID, name: String, symbol: String, displayOrder: Int, isArchived: Bool) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.displayOrder = displayOrder
            self.isArchived = isArchived
        }
    }
}
