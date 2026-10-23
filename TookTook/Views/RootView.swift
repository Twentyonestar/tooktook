import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var router = AppRouter.shared
    @AppStorage(PrefKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    @Query(filter: #Predicate<Stack> { $0.statusRaw == "pending" })
    private var pendingStacks: [Stack]

    /// 주소 변환 대상 스택. 개수가 아니라 구성(ID 목록)이 바뀔 때마다 변환을 다시 돌린다.
    /// 예: 대상 A가 삭제되고 B가 생겨 개수가 같아도 실행된다.
    @Query(filter: Stack.needsPlaceResolution, sort: \Stack.createdAt)
    private var placeResolutionTargets: [Stack]

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
                Task {
                    await NotificationPermission.shared.refresh()
                    await ReminderScheduler.refresh(pendingCount: pendingStacks.count)
                }
            }
            .interactiveDismissDisabled()
        }
        .task {
            // 권한 요청은 온보딩에서만 한다.
            StackStore(context: context).seedDefaultCategoriesIfNeeded()
            // 정상이라면 아무 일도 하지 않는다. 같은 ID의 동일 사본 정리, 같은 기본 카테고리 병합.
            DefaultCategory.tagIfNeverTagged(in: context)
            _ = try? DuplicateIDResolver.resolve(in: context)
            _ = try? DefaultCategoryMerger.mergeDuplicates(in: context)
            await NotificationPermission.shared.refresh()
            await ReminderScheduler.refresh(pendingCount: pendingStacks.count)
        }
        .onChange(of: pendingStacks.count) { _, count in
            Task { await ReminderScheduler.refresh(pendingCount: count) }
        }
        // 앱을 새로 켰을 때(scenePhase 변화가 없음)와 앱이 열린 채 스택이 생겼을 때도 변환되도록
        // 대상 구성 변화와 화면 활성화 두 경로에서 모두 실행한다. 겹치는 요청은 LocationEnricher가 이어서 처리한다.
        // .task(id:)는 ID가 바뀌면 진행 중인 변환을 취소하므로, 취소되지 않는 Task로 시작한다.
        .onChange(of: placeResolutionTargets.map(\.id), initial: true) {
            Task { await LocationEnricher.resolvePlaceLabels(in: context) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // 백그라운드에 있는 동안 날짜나 시간대가 바뀌었을 수 있다.
            AppClock.shared.tick()
            Task { await LocationEnricher.resolvePlaceLabels(in: context) }
            // 설정 앱에서 알림 권한을 바꾸고 돌아왔을 수 있다. 다시 확인하고 예약을 맞춘다.
            Task {
                await NotificationPermission.shared.refresh()
                await ReminderScheduler.refresh(pendingCount: pendingStacks.count)
            }
        }
    }
}
