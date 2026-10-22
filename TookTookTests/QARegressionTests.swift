import Foundation
import Testing
@testable import TookTook

/// 2026-10-23 실기기 QA에서 재현된 결함의 회귀 테스트
struct QARegressionTests {
    @Test func backupFilenameUsesLocalDate() {
        // 한국 시간 10월 23일 01:11 = UTC 10월 22일 16:11
        let exportedAt = ISO8601DateFormatter().date(from: "2026-10-22T16:11:54Z")!
        #expect(BackupService.defaultFilename(now: exportedAt, timeZone: TimeZone(identifier: "Asia/Seoul")!) == "tooktook-backup-2026-10-23")
        #expect(BackupService.defaultFilename(now: exportedAt, timeZone: TimeZone(identifier: "UTC")!) == "tooktook-backup-2026-10-22")
    }

    @Test func reminderNotificationOpensInbox() {
        let userInfo: [AnyHashable: Any] = [ReminderScheduler.destinationKey: ReminderScheduler.inboxDestination]
        #expect(NotificationRoute.tab(for: userInfo) == .inbox)
    }

    @Test func unknownNotificationDoesNotChangeTab() {
        #expect(NotificationRoute.tab(for: [:]) == nil)
        #expect(NotificationRoute.tab(for: [ReminderScheduler.destinationKey: "elsewhere"]) == nil)
    }
}
