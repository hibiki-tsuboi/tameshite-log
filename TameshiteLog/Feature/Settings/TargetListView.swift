import SwiftUI
import SwiftData

/// 観察対象の一覧。薬だけでなく、試したこと全般を貯めていく場所。
struct TargetListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ObservationTarget.createdAt) private var targets: [ObservationTarget]

    var body: some View {
        List {
            if targets.isEmpty {
                ContentUnavailableView(
                    "観察対象がありません",
                    systemImage: "pills",
                    description: Text("薬・サプリ・食事・運動・生活習慣など、変えてみたことを登録できます。")
                )
            }

            ForEach(TargetType.allCases) { type in
                let items = targets.filter { $0.type == type }
                if !items.isEmpty {
                    Section(type.label) {
                        ForEach(items) { target in
                            NavigationLink {
                                TargetEditorView(target: target)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(target.name, systemImage: type.symbolName)
                                    if !target.note.isEmpty {
                                        Text(target.note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("削除", systemImage: "trash", role: .destructive) {
                                    ObservationStore(context: context).delete(target)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("観察対象")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    TargetEditorView()
                } label: {
                    Label("観察対象を追加", systemImage: "plus")
                }
            }
        }
    }
}

/// 観察対象の追加・編集。
struct TargetEditorView: View {
    var target: ObservationTarget?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: TargetType = .medication
    @State private var note = ""

    var body: some View {
        Form {
            Section {
                TextField("名前", text: $name)
                Picker("種類", selection: $type) {
                    ForEach(TargetType.allCases) { type in
                        Label(type.label, systemImage: type.symbolName).tag(type)
                    }
                }
            }

            Section("メモ") {
                TextField("任意", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            if let target {
                Section {
                    Button("この観察対象を削除", systemImage: "trash", role: .destructive) {
                        ObservationStore(context: context).delete(target)
                        dismiss()
                    }
                } footer: {
                    Text("削除すると、この対象の実施記録も一緒に消えます。排便やまとめの記録は残ります。")
                }
            }
        }
        .navigationTitle(target == nil ? "観察対象を追加" : "観察対象の編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            guard let target else { return }
            name = target.name
            type = target.type
            note = target.note
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let target {
            target.name = trimmed
            target.type = type
            target.note = note
        } else {
            ObservationStore(context: context).createTarget(name: trimmed, type: type, note: note)
        }
        dismiss()
    }
}

#if DEBUG
#Preview {
    NavigationStack { TargetListView() }
        .modelContainer(SampleData.previewContainer)
}
#endif
