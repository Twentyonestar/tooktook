import SwiftUI

/// UserPreferences. 단축어 실행 경로에서도 읽어야 하므로 UserDefaults에 둔다.
enum PrefKey {
    static let reminderEnabled = "reminderEnabled"
    /// 자정 기준 분 단위. 기본 22:00
    static let reminderMinutes = "reminderMinutes"
    static let locationCaptureEnabled = "locationCaptureEnabled"
    static let appearance = "appearance"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
}

enum Preferences {
    static let defaultReminderMinutes = 22 * 60

    static var reminderEnabled: Bool { reminderEnabled(in: .standard) }

    static var reminderMinutes: Int { reminderMinutes(in: .standard) }

    static func reminderEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: PrefKey.reminderEnabled) as? Bool ?? true
    }

    static func reminderMinutes(in defaults: UserDefaults) -> Int {
        defaults.object(forKey: PrefKey.reminderMinutes) as? Int ?? defaultReminderMinutes
    }

    /// 저장된 분 값을 DatePicker에 쓸 오늘 날짜의 시각으로 바꾼다.
    static func reminderDate(fromMinutes minutes: Int, calendar: Calendar = .current, on day: Date = .now) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }

    /// DatePicker에서 고른 시각을 자정 기준 분 값으로 바꾼다. 날짜와 초는 버린다.
    static func reminderMinutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func reminderTimeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { reminderDate(fromMinutes: minutes.wrappedValue) },
            set: { minutes.wrappedValue = reminderMinutes(from: $0) }
        )
    }

    static var locationCaptureEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.locationCaptureEnabled) as? Bool ?? true
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "시스템 설정"
        case .light: "라이트"
        case .dark: "다크"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
