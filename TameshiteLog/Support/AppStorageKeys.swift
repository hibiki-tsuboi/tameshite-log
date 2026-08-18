import Foundation

/// @AppStorage のキーを 1 か所に集める。書き間違いで設定が読めなくなるのを防ぐため。
enum AppStorageKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let reminderEnabled = "reminderEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
}
