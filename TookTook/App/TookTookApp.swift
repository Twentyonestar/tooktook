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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let destination = response.notification.request.content.userInfo[ReminderScheduler.destinationKey] as? String
        guard destination == ReminderScheduler.inboxDestination else { return }
        await MainActor.run { AppRouter.shared.selectedTab = .inbox }
    }
}
