import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var router = AppRouter.shared
    @AppStorage(PrefKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    @Query(filter: #Predicate<Stack> { $0.statusRaw == "pending" })
    private var pendingStacks: [Stack]

    /// 좌표는 있는데 장소명이 아직 없는 스택. 개수가 바뀌면(새 좌표 저장, 변환 완료) 변환을 다시 돌린다.
    @Query(filter: #Predicate<Stack> { $0.locationStatusRaw == "captured" && $0.placeLabel == nil })
    private var unlabeledStacks: [Stack]

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
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { _ in })) {
            OnboardingView {
                hasCompletedOnboarding = true
                Task { await ReminderScheduler.refresh(pendingCount: pendingStacks.count) }
            }
            .interactiveDismissDisabled()
        }
        .task {
            // 권한 요청은 온보딩에서만 한다.
            StackStore(context: context).seedDefaultCategoriesIfNeeded()
            await ReminderScheduler.refresh(pendingCount: pendingStacks.count)
        }
        .onChange(of: pendingStacks.count) { _, count in
            Task { await ReminderScheduler.refresh(pendingCount: count) }
        }
        // 앱을 새로 켰을 때(scenePhase 변화가 없음)와 앱이 열린 채 스택이 생겼을 때도 변환되도록
        // 개수 변화와 화면 활성화 두 경로에서 모두 실행한다. 겹치는 실행은 LocationEnricher가 막는다.
        .task(id: unlabeledStacks.count) {
            await LocationEnricher.resolvePlaceLabels(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await LocationEnricher.resolvePlaceLabels(in: context) }
        }
    }
}
