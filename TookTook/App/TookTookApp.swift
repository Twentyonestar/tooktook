import SwiftData
import SwiftUI
import UserNotifications

@main
struct TookTookApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(PrefKey.appearance) private var appearance = Appearance.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(Appearance(rawValue: appearance)?.colorScheme)
        }
        .modelContainer(Persistence.container)
    }
}

enum AppTab: Hashable {
    case inbox
    case history
    case stats
    case settings
}

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var selectedTab: AppTab = .inbox
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // async 버전을 쓰면 iOS의 완료 처리가 메인 스레드 밖에서 불려 UIKit이 앱을 종료시킨다
    // (2026-10-23 실기기에서 알림을 누를 때 SIGABRT로 재현). 완료 핸들러 버전으로 메인에서 끝낸다.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let tab = NotificationRoute.tab(for: response.notification.request.content.userInfo)
        DispatchQueue.main.async {
            if let tab {
                AppRouter.shared.selectedTab = tab
            }
            completionHandler()
        }
    }
}

/// 알림의 userInfo로 열 화면을 정한다.
enum NotificationRoute {
    static func tab(for userInfo: [AnyHashable: Any]) -> AppTab? {
        guard userInfo[ReminderScheduler.destinationKey] as? String == ReminderScheduler.inboxDestination else { return nil }
        return .inbox
    }
}
