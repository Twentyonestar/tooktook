import AppIntents

/// Back Tap·단축어·잠금화면 컨트롤에서 실행된다. 앱 화면을 열지 않고 스택만 남긴다.
struct CaptureStackIntent: AppIntent {
    static let title: LocalizedStringResource = "지출 스택 남기기"
    static let description = IntentDescription("앱을 열지 않고 지금 시각으로 지출 스택을 저장합니다. 금액과 카테고리는 나중에 정리해요.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Persistence.container.mainContext
        let store = StackStore(context: context)

        // 저장에 실패하면 여기서 오류가 던져져 단축어에 실패로 표시된다.
        let stack = try store.createStack(source: .appIntent)

        await LocationEnricher.attachLocation(to: stack, in: context)
        await ReminderScheduler.refresh(pendingCount: store.pendingCount())

        let time = stack.createdAt.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "\(time) 스택을 남겼어요")
    }
}

struct TookTookShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureStackIntent(),
            phrases: [
                "\(.applicationName)에 스택 남기기",
                "\(.applicationName) 스택",
            ],
            shortTitle: "스택 남기기",
            systemImageName: "square.stack.3d.down.right.fill"
        )
    }
}
