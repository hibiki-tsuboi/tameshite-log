import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 引き継ぎファイルを選んでから復元するまでの一連。呼ぶ側は、きっかけのボタンだけ持つ。
///
/// 初回起動とデータ管理の 2 か所から同じ操作を始めるので、状態も確認の文言もここに 1 つだけ置く。
/// 同じ操作を画面ごとに書くと、置き換わる側の件数のようにあとから足した一文が片方だけになる。
extension View {
    /// - Parameters:
    ///   - isPresented: ファイル選択を開くきっかけ。
    ///   - onRestore: 復元が通ったあとに呼ぶ。画面ごとの後片付けに使う。
    func transferRestore(isPresented: Binding<Bool>, onRestore: @escaping () -> Void = {}) -> some View {
        modifier(TransferRestoreModifier(isPresented: isPresented, onRestore: onRestore))
    }
}

private struct TransferRestoreModifier: ViewModifier {
    @Binding var isPresented: Bool
    var onRestore: () -> Void

    @Environment(\.modelContext) private var context

    /// 読めたが、まだ適用していないファイルの中身。確認を挟むために持つ。
    @State private var pendingArchive: TransferArchive?
    /// 置き換わる側の量。復元してからでは数えられないので、確認を出す前に控える。
    @State private var replacedContent: String?
    @State private var isConfirming = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json]) { result in
                load(result)
            }
            .confirmationDialog(
                "引き継ぎファイルから復元しますか？",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("復元", role: .destructive) { restore() }
                Button("キャンセル", role: .cancel) { clearPending() }
            } message: {
                if let confirmationMessage { Text(confirmationMessage) }
            }
            .alert("読み込めませんでした", isPresented: hasError) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
    }

    private var hasError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    /// 入ってくる側と、置き換わる側を、同じ言葉の件数で並べる。
    /// ファイル名だけでは目的のものか読めないし、いまの記録が消えることも件数がないと伝わらない。
    private var confirmationMessage: String? {
        guard let pendingArchive else { return nil }
        let incoming = "\(Formatting.mediumDate(pendingArchive.createdAt))に作成 ・ \(pendingArchive.contentDescription)"
        // 何も入っていない端末なら、置き換えで失われるものがない。新しい端末で最初に開いた
        // ときがこれで、そこで「すべて置き換わります」と言うと、無いものを心配させる。
        guard let replacedContent else { return incoming }
        return incoming + "\n\nいまのデータ（\(replacedContent)）はすべて置き換わります。この操作は取り消せません。"
    }

    private func clearPending() {
        pendingArchive = nil
        replacedContent = nil
    }

    private func load(_ result: Result<URL, Error>) {
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
                    errorMessage = "このファイルは新しいバージョンのアプリで作られています。アプリを更新してから読み込んでください。"
                    return
                }
                pendingArchive = archive
                replacedContent = ObservationStore(context: context).contentDescription()
                isConfirming = true
            } catch {
                errorMessage = "ファイルを読み取れませんでした。引き継ぎファイルかどうか確かめてください。"
            }
        }
    }

    private func restore() {
        guard let archive = pendingArchive else { return }
        clearPending()
        do {
            try ObservationStore(context: context).restore(from: archive)
        } catch {
            // 保存が通らなければ何も書き換わっていない。
            errorMessage = "復元できませんでした。いまのデータはそのまま残っています。"
            return
        }
        onRestore()
        Task {
            await NotificationService.refreshDailyReminder(
                enabled: archive.reminder.isEnabled,
                hour: archive.reminder.hour,
                minute: archive.reminder.minute
            )
        }
    }
}
