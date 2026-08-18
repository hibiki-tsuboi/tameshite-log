import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("観察") {
                    NavigationLink { PlanListView() } label: {
                        Label("観察プラン管理", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink { TargetListView() } label: {
                        Label("観察対象管理", systemImage: "pills")
                    }
                    NavigationLink { RecordItemsView() } label: {
                        Label("記録項目", systemImage: "checklist")
                    }
                }

                Section("アプリ") {
                    NavigationLink { NotificationSettingsView() } label: {
                        Label("通知", systemImage: "bell")
                    }
                    NavigationLink { ExportView() } label: {
                        Label("書き出し", systemImage: "square.and.arrow.up")
                    }
                    NavigationLink { DataManagementView() } label: {
                        Label("データ管理", systemImage: "externaldrive")
                    }
                    NavigationLink { AboutView() } label: {
                        Label("アプリについて", systemImage: "info.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle("設定")
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .modelContainer(SampleData.previewContainer)
}
#endif
