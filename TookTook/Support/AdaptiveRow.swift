import SwiftUI

/// 이름과 금액을 한 줄에 놓는 행. 손쉬운 사용의 큰 글자 크기에서는 한 글자씩 끊기지 않도록 세로로 쌓는다.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                leading
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: spacing) {
                leading
                Spacer(minLength: 8)
                trailing
            }
        }
    }
}
