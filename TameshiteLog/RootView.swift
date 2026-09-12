import SwiftUI
import SwiftData

/// 初回起動時はオンボーディング、以降はタブ画面。
struct RootView: View {
    @AppStorage(AppStorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}

enum MainTab: Hashable {
    case record
    case compare
    case history
    case settings
}

struct MainTabView: View {
    @State private var selection: MainTab

    @AppStorage(AppStorageKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(AppStorageKey.reminderHour) private var reminderHour = AppStorageKey.defaultReminderHour
    @AppStorage(AppStorageKey.reminderMinute) private var reminderMinute = AppStorageKey.defaultReminderMinute

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let initial: MainTab =
            if arguments.contains("-compareTab") { .compare }
            else if arguments.contains("-historyTab") { .history }
            else if arguments.contains("-settingsTab") { .settings }
            else { .record }
        _selection = State(initialValue: initial)
        #else
        _selection = State(initialValue: .record)
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("記録", systemImage: "square.and.pencil", value: MainTab.record) {
                TodayView()
            }
            Tab("比較", systemImage: "arrow.left.arrow.right", value: MainTab.compare) {
                TrendView()
            }
            Tab("履歴", systemImage: "calendar", value: MainTab.history) {
                MonthCalendarView()
            }
            Tab("設定", systemImage: "gearshape", value: MainTab.settings) {
                SettingsView()
            }
        }
        .task {
            // 通知の許可はあとから取り消せるし、時刻の設定も端末側で変わりうる。
            // 起動のたびに設定どおりに登録し直しておく。
            await NotificationService.refreshDailyReminder(
                enabled: reminderEnabled,
                hour: reminderHour,
                minute: reminderMinute
            )
        }
    }
}

#if DEBUG
#Preview {
    MainTabView()
        .modelContainer(SampleData.previewContainer)
}
#endif
