import SwiftUI

extension Int64 {
    var krwText: String { "\(formatted(.number))원" }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }

    func isDate(_ date: Date, inSameMonthAs other: Date) -> Bool {
        isDate(date, equalTo: other, toGranularity: .month)
    }
}

/// 숫자만 남긴 금액 입력 문자열을 Int64로 바꾼다.
func parseAmount(_ text: String) -> Int64 {
    Int64(text.filter(\.isNumber)) ?? 0
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "문제가 생겼어요",
            isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } }),
            actions: { Button("확인", role: .cancel) {} },
            message: { Text(message.wrappedValue ?? "") }
        )
    }
}

/// 통계·내역 화면에서 같이 쓰는 월 이동 컨트롤
struct MonthSwitcher: View {
    @Binding var month: Date

    private var calendar: Calendar { .current }
    private var isCurrentMonth: Bool { calendar.isDate(month, inSameMonthAs: .now) }

    var body: some View {
        HStack {
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("이전 달")

            Spacer()
            Text(month.formatted(.dateTime.year().month(.wide)))
                .font(.headline)
            Spacer()

            Button {
                move(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isCurrentMonth)
            .accessibilityLabel("다음 달")
        }
        .buttonStyle(.borderless)
    }

    private func move(by value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: month) {
            month = calendar.startOfMonth(for: next)
        }
    }
}
