import SwiftUI

/// 카테고리 아이콘. 손대지 않은 기본 카테고리는 Apple 이모지로, 나머지는 저장된 SF Symbol로 그린다.
/// 이모지는 색을 입힐 수 없으므로 foregroundStyle은 SF Symbol일 때만 적용된다.
struct CategoryIcon: View {
    let category: ExpenseCategory?
    var fallbackSymbol = "questionmark.circle"

    var body: some View {
        if let category, let emoji = DefaultCategory.emoji(defaultKey: category.defaultKey, symbol: category.symbol) {
            Text(emoji)
        } else {
            Image(systemName: category?.symbol ?? fallbackSymbol)
        }
    }
}
