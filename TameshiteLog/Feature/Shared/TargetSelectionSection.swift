import SwiftUI
import SwiftData

/// フェーズに紐づける観察対象を選ぶセクション。フェーズの新規作成と編集で共有する。
struct TargetSelectionSection: View {
    @Binding var selection: Set<PersistentIdentifier>
    @Query(sort: \ObservationTarget.createdAt) private var targets: [ObservationTarget]

    var body: some View {
        Section {
            if targets.isEmpty {
                Text("まだ観察対象がありません")
                    .foregroundStyle(.secondary)
            }
            ForEach(targets) { target in
                Button {
                    toggle(target)
                } label: {
                    HStack {
                        Label(target.name, systemImage: target.type.symbolName)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(target.type.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if selection.contains(target.persistentModelID) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .accessibilityAddTraits(selection.contains(target.persistentModelID) ? [.isSelected] : [])
            }
            NavigationLink {
                TargetEditorView()
            } label: {
                Label("観察対象を追加", systemImage: "plus")
            }
        } header: {
            Text("観察対象")
        } footer: {
            Text("薬に限らず、サプリ・食事・運動・生活習慣など「変えてみたこと」を登録できます。")
        }
    }

    private func toggle(_ target: ObservationTarget) {
        let id = target.persistentModelID
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

/// 選択中の ID から実体を引き直す。SwiftData の識別子だけを状態に持つことで、
/// 途中で対象が削除されても壊れないようにしている。
extension Array where Element == ObservationTarget {
    func matching(_ ids: Set<PersistentIdentifier>) -> [ObservationTarget] {
        filter { ids.contains($0.persistentModelID) }
    }
}
