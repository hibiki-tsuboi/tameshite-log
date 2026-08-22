import Foundation

/// @AppStorage のキーを 1 か所に集める。書き間違いで設定が読めなくなるのを防ぐため。
///
/// 文字列と数値の定数だけなので `nonisolated`。既定が MainActor 隔離なので、
/// これを付けないと `TransferArchive` のような隔離のない型から参照できない。
nonisolated enum AppStorageKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let reminderEnabled = "reminderEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"

    /// リマインダーの既定時刻。キーが無いときに @AppStorage が使う値と、
    /// 引き継ぎファイルを読むときに使う値を同じにしておくため 1 か所に置く。
    static let defaultReminderHour = 21
    static let defaultReminderMinute = 0
}
