import Foundation
import UserNotifications

/// 1 日 1 回の記録リマインダー。
///
/// MVP では服薬通知は扱わないが、識別子と組み立てを分けてあるので
/// あとから対象ごとの通知を足すときもここを広げるだけで済む。
enum NotificationService {
    static let dailyReminderIdentifier = "daily-record-reminder"

    private static var center: UNUserNotificationCenter { .current() }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// 設定画面の状態をそのまま通知センターに反映する。
    /// 冪等なので、トグルや時刻を変えるたびに呼んでよい。
    static func refreshDailyReminder(enabled: Bool, hour: Int, minute: Int) async {
        cancelDailyReminder()
        guard enabled else { return }
        guard await authorizationStatus() == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "ブリストルログ"
        content.body = "今日の記録を残しませんか？"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    static func cancelDailyReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
    }
}
