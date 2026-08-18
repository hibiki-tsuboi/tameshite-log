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
    case today
    case trend
    case calendar
    case settings
}

struct MainTabView: View {
    @State private var selection: MainTab = .today

    @AppStorage(AppStorageKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(AppStorageKey.reminderHour) private var reminderHour = 21
    @AppStorage(AppStorageKey.reminderMinute) private var reminderMinute = 0

    var body: some View {
        TabView(selection: $selection) {
            Tab("今日", systemImage: "checklist", value: MainTab.today) {
                TodayView()
            }
            Tab("経過", systemImage: "chart.xyaxis.line", value: MainTab.trend) {
                TrendView()
            }
            Tab("カレンダー", systemImage: "calendar", value: MainTab.calendar) {
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
