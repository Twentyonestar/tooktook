import AppIntents
import SwiftData

/// Back Tap·단축어·잠금화면 컨트롤에서 실행된다. 앱 화면을 열지 않고 스택만 남긴다.
struct CaptureStackIntent: AppIntent {
    static let title: LocalizedStringResource = "지출 스택 남기기"
    static let description = IntentDescription("앱을 열지 않고 지금 시각으로 지출 스택을 저장합니다. 금액과 카테고리는 나중에 정리해요.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 저장소를 열 수 없거나 저장에 실패하면 오류가 던져져 단축어에 실패로 표시된다.
        let (stack, context) = try Self.saveStack(using: StoreController.shared)
        let store = StackStore(context: context)

        // 아래 두 작업은 실패해도 오류를 던지지 않는다. 스택 저장 성공 여부와 분리.
        // 알림 갱신을 먼저 해서, 위치 조회 중 실행이 끊겨도 알림은 최신 상태로 남게 한다.
        await ReminderScheduler.refresh(pendingCount: store.pendingCount())
        await LocationEnricher.attachLocation(to: stack, in: context)

        let time = stack.createdAt.formatted(date: .omitted, time: .shortened)
        return .result(dialog: "\(time) 스택을 남겼어요")
    }

    /// 로컬 저장소에만 의존한다. 네트워크·위치·알림과 무관하게 여기까지 성공해야 '남겼어요'를 보여준다.
    @MainActor
    static func saveStack(using controller: StoreController) throws -> (Stack, ModelContext) {
        // 앱 실행 때 열기에 실패했더라도 같은 파일로 한 번 더 시도한다. 새 저장소는 만들지 않는다.
        if controller.container == nil { controller.retry() }
        let context = try controller.requireContainer().mainContext
        let stack = try StackStore(context: context).createStack(source: .appIntent)
        return (stack, context)
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
