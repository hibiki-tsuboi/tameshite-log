import SwiftUI
import UIKit
import UserNotifications

/// 1 日 1 回の記録リマインダーの設定。
struct NotificationSettingsView: View {
    @AppStorage(AppStorageKey.reminderEnabled) private var isEnabled = false
    @AppStorage(AppStorageKey.reminderHour) private var hour = 21
    @AppStorage(AppStorageKey.reminderMinute) private var minute = 0

    @Environment(\.openURL) private var openURL
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                Toggle("毎日のリマインダー", isOn: $isEnabled)
                if isEnabled {
                    DatePicker("通知する時刻", selection: timeBinding, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("記録リマインダー")
            } footer: {
                Text("「今日の記録を残しませんか？」と 1 日 1 回お知らせします。")
            }

            if status == .denied {
                Section {
                    Label("通知が許可されていません", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                } footer: {
                    Text("iOS の「設定」＞「通知」から、ためしてログの通知を許可してください。")
                }
            }

            Section {
                Text("服薬時間のお知らせは、いまのところ対応していません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .task { status = await NotificationService.authorizationStatus() }
        .onChange(of: isEnabled) { _, _ in Task { await apply() } }
        .onChange(of: hour) { _, _ in Task { await apply() } }
        .onChange(of: minute) { _, _ in Task { await apply() } }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = components.hour ?? hour
                minute = components.minute ?? minute
            }
        )
    }

    /// 設定を通知センターへ反映する。許可が下りなければトグルを元に戻す。
    private func apply() async {
        if isEnabled {
            if await NotificationService.authorizationStatus() == .notDetermined {
                await NotificationService.requestAuthorization()
            }
            status = await NotificationService.authorizationStatus()
            if status != .authorized {
                isEnabled = false
                return
            }
        } else {
            status = await NotificationService.authorizationStatus()
        }
        await NotificationService.refreshDailyReminder(enabled: isEnabled, hour: hour, minute: minute)
    }
}

#Preview {
    NavigationStack { NotificationSettingsView() }
}
