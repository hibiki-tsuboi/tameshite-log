import SwiftUI
import SwiftData

/// フェーズの編集。期間をあとから直せることが、経過観察では大事になる。
struct PhaseEditorView: View {
    @Bindable var phase: ObservationPhase

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ObservationTarget.createdAt) private var targets: [ObservationTarget]
    @State private var selectedTargetIDs: Set<PersistentIdentifier> = []
    @State private var hasEndDate = false
    @State private var endDate = Date.now

    var body: some View {
        Form {
            Section("フェーズ") {
                TextField("フェーズ名", text: $phase.name)
                Picker("種類", selection: $phase.type) {
                    ForEach(PhaseType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
            }

            Section {
                DatePicker("開始日", selection: $phase.startDate, displayedComponents: .date)
                Toggle("終了日を設定", isOn: $hasEndDate)
                if hasEndDate {
                    DatePicker("終了日", selection: $endDate, in: phase.startDate..., displayedComponents: .date)
                }
            } header: {
                Text("期間")
            } footer: {
                Text(hasEndDate ? "" : "終了日なしは「継続中」として扱われます。")
            }

            TargetSelectionSection(selection: $selectedTargetIDs)

            Section("メモ") {
                TextField("任意", text: $phase.note, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                Button("このフェーズを削除", systemImage: "trash", role: .destructive) {
                    ObservationStore(context: context).delete(phase)
                    dismiss()
                }
            }
        }
        .navigationTitle("フェーズの編集")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedTargetIDs = Set(phase.targets.map(\.persistentModelID))
            hasEndDate = phase.endDate != nil
            endDate = phase.endDate ?? Date.now
        }
        .onChange(of: selectedTargetIDs) { _, newValue in
            phase.targets = targets.matching(newValue)
        }
        .onChange(of: hasEndDate) { _, newValue in
            phase.endDate = newValue ? Calendar.current.startOfDay(for: endDate) : nil
        }
        .onChange(of: endDate) { _, newValue in
            guard hasEndDate else { return }
            phase.endDate = Calendar.current.startOfDay(for: newValue)
        }
    }
}
