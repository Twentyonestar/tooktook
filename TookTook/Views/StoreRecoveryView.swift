import SwiftUI

/// 저장소를 열지 못했을 때 보여준다. 원본을 지우는 동작은 일부러 두지 않는다.
struct StoreRecoveryView: View {
    let detail: String
    let preservedCopy: URL?
    let onRetry: () -> Void

    @State private var showGuide = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("기록을 불러오지 못했어요")
                    .font(.largeTitle.bold())
                Text("저장된 데이터를 안전하게 읽지 못했어요. 기존 기록을 보호하기 위해 새 데이터 저장소를 만들지 않았습니다.")
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button {
                        onRetry()
                    } label: {
                        Text("다시 시도하기").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showGuide.toggle()
                    } label: {
                        Text("복구 방법 확인하기").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .fontWeight(.semibold)

                if showGuide {
                    RecoveryGuide(preservedCopy: preservedCopy, detail: detail)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.default, value: showGuide)
    }
}

private struct RecoveryGuide: View {
    let preservedCopy: URL?
    let detail: String

    private let steps = [
        "앱을 완전히 종료한 뒤 다시 열어 보세요. 일시적인 문제라면 기록이 그대로 보여요.",
        "iPhone 저장 공간이 부족하면 열지 못할 수 있어요. 설정 › 일반 › iPhone 저장 공간에서 여유 공간을 확보해 주세요.",
        "App Store에서 툭툭가계부 업데이트가 있는지 확인해 주세요.",
        "기존 기록 파일은 지우지 않고 그대로 두었어요. 앱을 삭제하면 기록도 함께 지워지니 삭제하지 마세요.",
        "이전에 '기록 내보내기'로 저장한 백업 파일이 있다면 보관해 두세요. 저장소가 다시 열리면 설정 › 기록 가져오기로 되돌릴 수 있어요.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.bold())
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor.opacity(0.2)))
                        .accessibilityHidden(true)
                    Text(step)
                        .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            }
            if preservedCopy != nil {
                Text("문제 확인을 위해 열지 못한 기록 파일의 사본도 앱 안에 따로 보관했어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("오류 정보") {
                Text(detail)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote)
        }
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }
}
