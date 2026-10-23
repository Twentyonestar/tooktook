import Foundation
import SwiftData

/// 앱 코드는 별칭으로 현재 스키마 버전의 모델을 쓴다. 새 버전을 추가하면 별칭을 옮긴다.
typealias ExpenseCategory = SchemaV2.ExpenseCategory

extension SchemaV2 {
    /// PRD의 Category. Objective-C 런타임의 `Category` 타입과 겹치지 않도록 이름을 바꿨다.
    @Model
    final class ExpenseCategory {
        // CloudKit 호환: unique 없음, 필수 속성마다 기본값 (init이 항상 실제 값을 넣는다).
        var id: UUID = UUID()
        var name: String = ""
        var symbol: String = "ellipsis.circle.fill"
        var displayOrder: Int = 0
        var isArchived: Bool = false
        /// 기본 카테고리의 기기 공통 식별자(DefaultCategory.key). 사용자가 만든 카테고리는 nil.
        /// 이름을 바꾸거나 보관해도 유지되며, 여러 기기의 같은 기본 카테고리를 알아보는 데 쓴다.
        var defaultKey: String?

        init(id: UUID = UUID(), name: String, symbol: String, displayOrder: Int, isArchived: Bool = false, defaultKey: String? = nil) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.displayOrder = displayOrder
            self.isArchived = isArchived
            self.defaultKey = defaultKey
        }

        static var defaults: [(name: String, symbol: String)] {
            DefaultCategory.all.map { ($0.name, $0.symbol) }
        }

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
