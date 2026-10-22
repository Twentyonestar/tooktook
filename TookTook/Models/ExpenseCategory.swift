import Foundation
import SwiftData

/// 앱 코드는 별칭으로 현재 스키마 버전의 모델을 쓴다. 새 버전을 추가하면 별칭을 옮긴다.
typealias ExpenseCategory = SchemaV1.ExpenseCategory

extension SchemaV1 {
    /// PRD의 Category. Objective-C 런타임의 `Category` 타입과 겹치지 않도록 이름을 바꿨다.
    @Model
    final class ExpenseCategory {
        @Attribute(.unique) var id: UUID
        var name: String
        var symbol: String
        var displayOrder: Int
        var isArchived: Bool

        init(id: UUID = UUID(), name: String, symbol: String, displayOrder: Int, isArchived: Bool = false) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.displayOrder = displayOrder
            self.isArchived = isArchived
        }

        static let defaults: [(name: String, symbol: String)] = [
            ("식비", "fork.knife"),
            ("카페", "cup.and.saucer.fill"),
            ("교통", "bus.fill"),
            ("쇼핑", "bag.fill"),
            ("생활", "house.fill"),
            ("문화", "ticket.fill"),
            ("의료", "cross.case.fill"),
            ("기타", "ellipsis.circle.fill"),
        ]

        static let symbolChoices: [String] = [
            "fork.knife", "cup.and.saucer.fill", "bus.fill", "car.fill", "tram.fill",
            "bag.fill", "cart.fill", "house.fill", "ticket.fill", "film.fill",
            "gamecontroller.fill", "book.fill", "cross.case.fill", "pills.fill",
            "gift.fill", "pawprint.fill", "tshirt.fill", "wifi", "phone.fill",
            "graduationcap.fill", "airplane", "dumbbell.fill", "wineglass.fill",
            "ellipsis.circle.fill",
        ]
    }
}
