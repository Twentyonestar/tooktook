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

    static var reminderEnabled: Bool {
        UserDefaults.standard.object(forKey: PrefKey.reminderEnabled) as? Bool ?? true
    }

    static var reminderMinutes: Int {
        UserDefaults.standard.object(forKey: PrefKey.reminderMinutes) as? Int ?? defaultReminderMinutes
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
