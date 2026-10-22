import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var router = AppRouter.shared

    @Query(filter: #Predicate<Stack> { $0.statusRaw == "pending" })
    private var pendingStacks: [Stack]

    var body: some View {
        TabView(selection: $router.selectedTab) {
            InboxView()
                .tabItem { Label("스택", systemImage: "tray.full") }
                .badge(pendingStacks.count)
                .tag(AppTab.inbox)

            HistoryView()
                .tabItem { Label("내역", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.history)

            StatsView()
                .tabItem { Label("통계", systemImage: "chart.pie") }
                .tag(AppTab.stats)

            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .task {
            StackStore(context: context).seedDefaultCategoriesIfNeeded()
            if Preferences.reminderEnabled {
                await ReminderScheduler.requestAuthorizationIfNeeded()
            }
            await ReminderScheduler.refresh(pendingCount: pendingStacks.count)
        }
        .onChange(of: pendingStacks.count) { _, count in
            Task { await ReminderScheduler.refresh(pendingCount: count) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await LocationEnricher.resolvePlaceLabels(in: context) }
        }
    }
}
