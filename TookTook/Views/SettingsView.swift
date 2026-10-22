import AppIntents
import CoreLocation
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @AppStorage(PrefKey.reminderEnabled) private var reminderEnabled = true
    @AppStorage(PrefKey.reminderMinutes) private var reminderMinutes = Preferences.defaultReminderMinutes
    @AppStorage(PrefKey.locationCaptureEnabled) private var locationCaptureEnabled = true
    @AppStorage(PrefKey.appearance) private var appearance = Appearance.system.rawValue

    @State private var location = LocationService.shared
    @State private var notificationPermission = NotificationPermission.shared
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: BackupPayload?
    @State private var confirmClearLocations = false
    @State private var confirmDeleteAll = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    private var store: StackStore { StackStore(context: context) }

    var body: some View {
        NavigationStack {
            Form {
                Section("기록 방법") {
                    NavigationLink("뒷면 탭으로 스택 남기기") { BackTapGuideView() }
                    NavigationLink("잠금화면 컨트롤 추가하기") { LockScreenGuideView() }
                }

                Section {
                    Toggle("스택에 위치 함께 저장", isOn: $locationCaptureEnabled)
                    LabeledContent("위치 권한", value: authorizationText)
                    if location.authorizationStatus == .notDetermined {
                        Button("위치 권한 요청") { location.requestAuthorization() }
                    } else if !location.isAuthorized {
                        Button("설정에서 권한 변경") { openAppSettings() }
                    }
                    Button("저장된 위치 정보 모두 삭제", role: .destructive) { confirmClearLocations = true }
                } header: {
                    Text("위치")
                } footer: {
                    Text("위치는 어디서 쓴 돈인지 떠올리는 데만 쓰이고 기기 밖으로 나가지 않아요. 권한이 없어도 스택은 정상적으로 저장돼요.")
                }

                Section {
                    Toggle("정리 알림", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker("알림 시각", selection: Preferences.reminderTimeBinding($reminderMinutes), displayedComponents: .hourAndMinute)
                    }
                    if reminderAvailability == .blockedBySystem {
                        NotificationDeniedBanner()
                    }
                } header: {
                    Text("정리 알림")
                } footer: {
                    Text(reminderFooter)
                }

                Section("화면") {
                    Picker("화면 모드", selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.label).tag(option.rawValue)
                        }
                    }
                }

                Section("데이터") {
                    NavigationLink("카테고리 관리") { CategoryManagementView() }
                    Button("기록 내보내기") { prepareExport() }
                    Button("기록 가져오기") { showImporter = true }
                    Button("전체 데이터 삭제", role: .destructive) { confirmDeleteAll = true }
                }

                Section {
                    LabeledContent("버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("설정")
            .onChange(of: reminderEnabled) { _, enabled in
                Task {
                    if enabled { await ReminderScheduler.requestAuthorizationIfNeeded() }
                    await notificationPermission.refresh()
                    await ReminderScheduler.refresh(pendingCount: store.pendingCount())
                }
            }
            .onChange(of: reminderMinutes) { _, _ in
                Task { await ReminderScheduler.refresh(pendingCount: store.pendingCount()) }
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "tooktook-backup-\(Date.now.formatted(.iso8601.year().month().day()))"
            ) { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                loadImport(result)
            }
            .confirmationDialog("저장된 위치 정보를 모두 삭제할까요?", isPresented: $confirmClearLocations, titleVisibility: .visible) {
                Button("위치 정보 삭제", role: .destructive) { clearLocations() }
            } message: {
                Text("스택과 지출 기록은 그대로 남아요.")
            }
            .confirmationDialog(
                "백업으로 덮어쓸까요?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                titleVisibility: .visible
            ) {
                Button("현재 데이터를 지우고 가져오기", role: .destructive) { applyImport() }
            } message: {
                Text("지금 기기에 있는 스택과 지출 기록은 모두 백업 파일 내용으로 바뀌어요.")
            }
            .confirmationDialog("모든 데이터를 삭제할까요?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("전체 삭제", role: .destructive) { deleteAll() }
            } message: {
                Text("스택, 지출 기록, 카테고리가 모두 지워지고 되돌릴 수 없어요.")
            }
            .alert("완료", isPresented: Binding(get: { infoMessage != nil }, set: { if !$0 { infoMessage = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(infoMessage ?? "")
            }
            .errorAlert($errorMessage)
        }
    }

    private var reminderAvailability: ReminderAvailability {
        notificationPermission.availability(enabled: reminderEnabled)
    }

    /// 실제로 알림이 가지 않는 상태에서는 가는 것처럼 안내하지 않는다.
    private var reminderFooter: String {
        switch reminderAvailability {
        case .active, .unknown: "정리하지 않은 스택이 있을 때만 알려드려요."
        case .needsPermission: "알림 권한을 허용하면 이 시각에 알려드려요."
        case .blockedBySystem: "지금은 알림이 오지 않아요. 선택한 시각은 저장돼 있어서, 권한을 허용하면 바로 다시 예약돼요."
        case .off: "알림을 꺼도 언제든 스택 탭에서 정리할 수 있어요."
        }
    }

    private var authorizationText: String {
        switch location.authorizationStatus {
        case .notDetermined: "요청 전"
        case .authorizedWhenInUse: "앱 사용 중 허용"
        case .authorizedAlways: "항상 허용"
        case .denied: "거부됨"
        case .restricted: "제한됨"
        @unknown default: "알 수 없음"
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func prepareExport() {
        do {
            let data = try BackupService.encode(BackupService.makePayload(from: context))
            exportDocument = BackupDocument(data: data)
            showExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let payload = try BackupService.decode(Data(contentsOf: url))
            try BackupService.validate(payload)
            pendingImport = payload
        } catch {
            errorMessage = "백업 파일을 읽을 수 없어요. \(error.localizedDescription)"
        }
    }

    private func applyImport() {
        guard let payload = pendingImport else { return }
        pendingImport = nil
        do {
            try BackupService.restore(payload, into: context)
            infoMessage = "스택 \(payload.stacks.count)개, 지출 \(payload.transactions.count)건을 가져왔어요."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearLocations() {
        do {
            try store.clearAllLocations()
            infoMessage = "저장된 위치 정보를 삭제했어요."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAll() {
        do {
            try store.deleteAllData()
            infoMessage = "모든 데이터를 삭제했어요."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BackTapGuideView: View {
    var body: some View {
        GuideList(steps: BackTapGuide.steps, footnote: BackTapGuide.footnote) {
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        }
        .navigationTitle("뒷면 탭 설정")
    }
}

struct LockScreenGuideView: View {
    var body: some View {
        GuideList(steps: [
            "잠금화면을 길게 눌러 '사용자화'를 선택해요.",
            "잠금화면을 고른 뒤 아래쪽 컨트롤을 눌러 바꿔요.",
            "컨트롤 목록에서 '단축어'를 추가하고 '스택 남기기'를 선택해요.",
            "제어 센터에도 같은 방법으로 추가할 수 있어요.",
        ], footnote: "잠금화면 컨트롤은 iOS 18 이상에서 쓸 수 있어요.")
        .navigationTitle("잠금화면 컨트롤")
    }
}

private struct GuideList<Accessory: View>: View {
    let steps: [String]
    let footnote: String
    @ViewBuilder let accessory: Accessory

    init(steps: [String], footnote: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.steps = steps
        self.footnote = footnote
        self.accessory = accessory()
    }

    var body: some View {
        List {
            Section {
                accessory
            }
            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.accentColor.opacity(0.2)))
                            .accessibilityHidden(true)
                        Text(step)
                    }
                    .accessibilityElement(children: .combine)
                }
            } footer: {
                Text(footnote)
            }
        }
    }
}
