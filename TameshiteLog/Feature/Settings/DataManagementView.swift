import SwiftUI
import SwiftData

struct DataManagementView: View {
    @Environment(\.modelContext) private var context

    @State private var isConfirmingRecordDeletion = false
    @State private var isConfirmingFullDeletion = false

    @State private var transferFile: URL?
    @State private var isCreatingTransferFile = false
    @State private var isChoosingTransferFile = false
    @State private var creationError: String?

    var body: some View {
        Form {
            Section {
                Label("記録は端末の中だけに保存されます", systemImage: "iphone")
                Label("アカウント登録や外部への送信はありません", systemImage: "lock")
            } header: {
                Text("保存場所")
            } footer: {
                Text("他の端末との自動同期にはまだ対応していません。新しい端末へ移すときは、下の「データの引き継ぎ」を使ってください。")
            }

            Section {
                NavigationLink { ExportView() } label: {
                    Label("書き出し", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("記録を PDF・CSV で取り出せます。削除の前にも使えます。")
            }

            Section {
                if let transferFile {
                    ShareLink(item: transferFile) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("引き継ぎファイルを共有")
                                    .foregroundStyle(.primary)
                                Text(transferFile.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                } else if isCreatingTransferFile {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("作成しています…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // 押されるまで作らない。写真ごと詰めるので、画面を開いただけで
                    // 数 MB のファイルを毎回書くことになる。
                    Button("引き継ぎファイルを作る", systemImage: "doc.badge.plus") {
                        createTransferFile()
                    }
                }

                Button("引き継ぎファイルから復元", systemImage: "arrow.down.doc") {
                    isChoosingTransferFile = true
                }
            } header: {
                Text("データの引き継ぎ")
            } footer: {
                Text("新しい端末へ記録を移すためのファイルです。プラン・フェーズ・観察対象・記録に加えて、観察対象に添えた写真も入ります。処方箋が写っていることがあるので、人には渡さないでください。復元すると、いまのデータはすべて置き換わります。")
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
        .scrollContentBackground(.hidden)
        .appBackground()
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
        // 復元したら、作り置きのファイルはいま入れた中身より古い。共有できるまま残さない。
        .transferRestore(isPresented: $isChoosingTransferFile) { transferFile = nil }
        .alert("作成できませんでした", isPresented: hasCreationError) {
            Button("OK") { creationError = nil }
        } message: {
            if let creationError {
                Text(creationError)
            }
        }
    }

    // MARK: - 引き継ぎ

    private var hasCreationError: Binding<Bool> {
        Binding(get: { creationError != nil }, set: { if !$0 { creationError = nil } })
    }

    private func createTransferFile() {
        isCreatingTransferFile = true
        creationError = nil
        Task {
            do {
                // 組み立ては SwiftData を読むのでメインのまま。JSON にするところだけ外へ出す。
                // 写真を base64 で抱えるので、1 年ぶんだと数 MB になる。
                let archive = ObservationStore(context: context).makeTransferArchive()
                let data = try await Task.detached { try JSONEncoder().encode(archive) }.value
                let directory = try ExportService.prepareDirectory(named: "Transfer")
                let url = directory.appending(
                    path: ExportService.filename(planName: "", suffix: "引き継ぎ", extension: "json")
                )
                try data.write(to: url, options: .atomic)
                transferFile = url
            } catch {
                creationError = "引き継ぎファイルを作成できませんでした。"
            }
            isCreatingTransferFile = false
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { DataManagementView() }
        .modelContainer(SampleData.previewContainer)
}
#endif
