import AppIntents
import SwiftUI

/// 뒷면 탭 연결 순서. 시스템 설정은 앱이 대신할 수 없어 사용자가 직접 진행한다.
enum BackTapGuide {
    static let steps = [
        "아래 버튼으로 단축어 앱을 열고 + 를 눌러 새 단축어를 만들어요.",
        "동작 검색에서 '툭툭가계부'의 '지출 스택 남기기'를 추가하고, 이름을 '스택 남기기'로 저장해요.",
        "설정 > 손쉬운 사용 > 터치 > 뒷면 탭 > 이중 탭에서 맨 아래 '스택 남기기'를 골라요.",
        "결제 후 iPhone 뒷면을 두 번 톡톡 두드리면 스택이 저장돼요.",
    ]

    static let footnote = "뒷면 탭 목록에는 단축어 앱에 직접 만든 단축어만 보여요. 검색에 '툭툭가계부'가 나오지 않으면 툭툭가계부를 한 번 실행한 뒤 다시 찾아 주세요."
}

/// 첫 실행 때 한 번 보여준다. 뒷면 탭 실행 경로에는 화면이 없어 권한을 물을 수 없으므로 여기서 미리 받는다.
struct OnboardingView: View {
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case intro
        case location
        case notification
        case backTap
    }

    @AppStorage(PrefKey.locationCaptureEnabled) private var locationCaptureEnabled = true
    @AppStorage(PrefKey.reminderEnabled) private var reminderEnabled = true
    @AppStorage(PrefKey.reminderMinutes) private var reminderMinutes = Preferences.defaultReminderMinutes
    @State private var location = LocationService.shared
    @State private var step: Step = .intro
    @State private var waitingForLocation = false

    var body: some View {
        VStack(spacing: 0) {
            ProgressDots(count: Step.allCases.count, current: step.rawValue)
                .padding(.top, 24)

            ScrollView {
                content
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
            }

            actions
                .controlSize(.large)
                .fontWeight(.semibold)
                .padding(24)
        }
        .animation(.default, value: step)
        .onChange(of: location.authorizationStatus) { _, status in
            guard waitingForLocation, status != .notDetermined else { return }
            waitingForLocation = false
            locationCaptureEnabled = location.isAuthorized
            advance()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro:
            OnboardingPage(
                symbol: "square.stack.3d.down.right.fill",
                title: "결제할 땐 톡톡,\n정리는 나중에",
                message: "결제할 때 iPhone 뒷면을 두 번 두드리면 시각이 담긴 스택이 저장돼요. 금액과 카테고리는 하루 끝에 한 번에 정리하면 돼요."
            )
        case .location:
            OnboardingPage(
                symbol: "location.fill",
                title: "어디서 쓴 돈인지\n떠올리기 쉽게",
                message: "스택을 남긴 위치를 함께 저장하면 나중에 정리할 때 기억이 쉬워져요. 위치는 기기에만 저장되고, 허용하지 않아도 스택은 정상적으로 남아요."
            )
        case .notification:
            VStack(alignment: .leading, spacing: 24) {
                OnboardingPage(
                    symbol: "bell.badge.fill",
                    title: "하루의 지출은\n언제 정리할까요?",
                    message: "정리하지 않은 스택이 있을 때만 이 시각에 알려드려요. 설정에서 언제든 바꿀 수 있어요."
                )
                VStack(spacing: 0) {
                    Toggle("정리 알림 받기", isOn: $reminderEnabled)
                        .padding(.vertical, 12)
                    if reminderEnabled {
                        Divider()
                        DatePicker(
                            "알림 시각",
                            selection: Preferences.reminderTimeBinding($reminderMinutes),
                            displayedComponents: .hourAndMinute
                        )
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 16)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
                .animation(.default, value: reminderEnabled)
            }
        case .backTap:
            VStack(alignment: .leading, spacing: 24) {
                OnboardingPage(
                    symbol: "hand.tap.fill",
                    title: "뒷면 탭을\n연결해 주세요",
                    message: "아래 순서대로 한 번만 설정하면 돼요. 설정 탭에서 언제든 다시 볼 수 있어요."
                )
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(BackTapGuide.steps.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.bold())
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.accentColor.opacity(0.2)))
                                .accessibilityHidden(true)
                            Text(text)
                                .font(.subheadline)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch step {
        case .intro:
            primaryButton("시작하기") { advance() }
        case .location:
            VStack(spacing: 8) {
                primaryButton("위치 허용하기") { requestLocation() }
                secondaryButton("나중에") {
                    locationCaptureEnabled = false
                    advance()
                }
            }
        case .notification:
            // 알림을 쓰기로 한 경우에만 권한을 묻는다. 거부해도 다음 단계로 넘어간다.
            primaryButton("계속") {
                Task {
                    if reminderEnabled {
                        await ReminderScheduler.requestAuthorizationIfNeeded()
                    }
                    advance()
                }
            }
        case .backTap:
            primaryButton("시작하기") { onFinish() }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
    }

    private func requestLocation() {
        // 이미 결정된 상태면 시스템 창이 뜨지 않으므로 바로 넘어간다.
        guard location.authorizationStatus == .notDetermined else {
            locationCaptureEnabled = location.isAuthorized
            advance()
            return
        }
        waitingForLocation = true
        location.requestAuthorization()
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        } else {
            onFinish()
        }
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 20 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(count)단계 중 \(current + 1)단계")
    }
}
