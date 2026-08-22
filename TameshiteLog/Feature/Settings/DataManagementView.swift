import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataManagementView: View {
    @Environment(\.modelContext) private var context

    @State private var isConfirmingRecordDeletion = false
    @State private var isConfirmingFullDeletion = false

    @State private var transferFile: URL?
    @State private var isCreatingTransferFile = false
    @State private var isChoosingTransferFile = false
    /// 読み込めたが、まだ適用していないファイルの中身。確認を挟むために持つ。
    @State private var pendingArchive: TransferArchive?
    @State private var isConfirmingRestore = false
    @State private var transferError: String?

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
        .fileImporter(isPresented: $isChoosingTransferFile, allowedContentTypes: [.json]) { result in
            loadTransferFile(result)
        }
        .confirmationDialog(
            "引き継ぎファイルから復元しますか？",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("復元", role: .destructive) { restore() }
            Button("キャンセル", role: .cancel) { pendingArchive = nil }
        } message: {
            if let pendingArchive {
                // 中身と作った日を出す。選んだファイルが目的のものかは、名前だけでは読めない。
                Text("\(Formatting.mediumDate(pendingArchive.createdAt))に作成 ・ \(pendingArchive.contentDescription)\n\nいまのデータはすべて置き換わります。この操作は取り消せません。")
            }
        }
        .alert("読み込めませんでした", isPresented: hasTransferError) {
            Button("OK") { transferError = nil }
        } message: {
            if let transferError {
                Text(transferError)
            }
        }
    }

    // MARK: - 引き継ぎ

    private var hasTransferError: Binding<Bool> {
        Binding(get: { transferError != nil }, set: { if !$0 { transferError = nil } })
    }

    private func createTransferFile() {
        isCreatingTransferFile = true
        transferError = nil
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
                transferError = "引き継ぎファイルを作成できませんでした。"
            }
            isCreatingTransferFile = false
        }
    }

    private func loadTransferFile(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        Task {
            // アプリの外のファイルなので、読む間だけ許可を取る。
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let archive = try await Task.detached {
                    try JSONDecoder().decode(TransferArchive.self, from: data)
                }.value
                guard archive.formatVersion <= TransferArchive.currentFormatVersion else {
                    transferError = "このファイルは新しいバージョンのアプリで作られています。アプリを更新してから読み込んでください。"
                    return
                }
                pendingArchive = archive
                isConfirmingRestore = true
            } catch {
                transferError = "ファイルを読み取れませんでした。引き継ぎファイルかどうか確かめてください。"
            }
        }
    }

    private func restore() {
        guard let archive = pendingArchive else { return }
        pendingArchive = nil
        do {
            try ObservationStore(context: context).restore(from: archive)
        } catch {
            // 保存が通らなければ何も書き換わっていない。
            transferError = "復元できませんでした。いまのデータはそのまま残っています。"
            return
        }
        // 作り置きのファイルは、いま入れた中身より古い。共有できるまま残さない。
        transferFile = nil
        Task {
            await NotificationService.refreshDailyReminder(
                enabled: archive.reminder.isEnabled,
                hour: archive.reminder.hour,
                minute: archive.reminder.minute
            )
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { DataManagementView() }
        .modelContainer(SampleData.previewContainer)
}
#endif
