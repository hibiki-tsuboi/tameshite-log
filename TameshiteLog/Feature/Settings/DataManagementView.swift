import SwiftUI
import SwiftData

struct DataManagementView: View {
    @Environment(\.modelContext) private var context

    @State private var isConfirmingRecordDeletion = false
    @State private var isConfirmingFullDeletion = false

    var body: some View {
        Form {
            Section {
                Label("記録は端末の中だけに保存されます", systemImage: "iphone")
                Label("アカウント登録や外部への送信はありません", systemImage: "lock")
            } header: {
                Text("保存場所")
            } footer: {
                Text("他の端末との同期にはまだ対応していません。控えを残すには「書き出し」から CSV を保存してください。")
            }

            Section {
                NavigationLink { ExportView() } label: {
                    Label("書き出し", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("記録を PDF・CSV で取り出せます。削除の前にも使えます。")
            }

            Section {
                Button("記録をすべて削除", systemImage: "trash", role: .destructive) {
                    isConfirmingRecordDeletion = true
                }
            } footer: {
                Text("排便・1日のまとめ・観察対象の実施記録を消します。プランと観察対象は残ります。")
            }

            Section {
                Button("すべてのデータを削除", systemImage: "exclamationmark.triangle", role: .destructive) {
                    isConfirmingFullDeletion = true
                }
            } footer: {
                Text("プラン・フェーズ・観察対象を含め、このアプリのデータをすべて消します。")
            }

            #if DEBUG
            Section {
                Button("サンプルデータを読み込む", systemImage: "wand.and.stars") {
                    SampleData.populate(context)
                }
            } header: {
                Text("開発用")
            } footer: {
                Text("30日分の架空データに置き換えます。UI 確認用で、医学的な意味はありません。")
            }
            #endif
        }
        .navigationTitle("データ管理")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("記録をすべて削除しますか？", isPresented: $isConfirmingRecordDeletion, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                ObservationStore(context: context).deleteAllRecords()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
        .confirmationDialog("すべてのデータを削除しますか？", isPresented: $isConfirmingFullDeletion, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                ObservationStore(context: context).deleteEverything()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("プラン・フェーズ・観察対象・記録がすべて消えます。この操作は取り消せません。")
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { DataManagementView() }
        .modelContainer(SampleData.previewContainer)
}
#endif
