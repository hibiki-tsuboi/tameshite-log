import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    SectionCard(title: "観察", systemImage: "point.3.connected.trianglepath.dotted") {
                        VStack(spacing: 0) {
                            NavigationLink { PlanListView() } label: {
                                SettingsRow(
                                    title: "観察プラン",
                                    detail: "期間とフェーズを管理",
                                    systemImage: "list.bullet.rectangle"
                                )
                            }
                            Divider()
                            NavigationLink { TargetListView() } label: {
                                SettingsRow(
                                    title: "観察対象",
                                    detail: "薬・食事・習慣などを管理",
                                    systemImage: "pills"
                                )
                            }
                            Divider()
                            NavigationLink { RecordItemsView() } label: {
                                SettingsRow(
                                    title: "記録項目",
                                    detail: "日々入力する内容を選択",
                                    systemImage: "checklist"
                                )
                            }
                        }
                    }

                    SectionCard(title: "アプリとデータ", systemImage: "slider.horizontal.3") {
                        VStack(spacing: 0) {
                            NavigationLink { NotificationSettingsView() } label: {
                                SettingsRow(title: "通知", detail: "記録時刻のお知らせ", systemImage: "bell")
                            }
                            Divider()
                            NavigationLink { ExportView() } label: {
                                SettingsRow(title: "書き出し", detail: "記録と比較結果を共有", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            NavigationLink { DataManagementView() } label: {
                                SettingsRow(title: "データ管理", detail: "引き継ぎと復元", systemImage: "externaldrive")
                            }
                            Divider()
                            NavigationLink { AboutView() } label: {
                                SettingsRow(title: "アプリについて", detail: "使い方・プライバシー", systemImage: "info.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .readableWidth()
            }
            .appBackground()
            .navigationTitle("設定")
        }
    }
}

private struct SettingsRow: View {
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.11), in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(SampleData.previewContainer)
}
#endif
