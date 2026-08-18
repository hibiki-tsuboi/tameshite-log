import SwiftUI
import SwiftData

/// フェーズの編集。期間をあとから直せることが、経過観察では大事になる。
///
/// 期間の変更は `ObservationStore` を通す。フェーズ同士が重なると、その日の記録が
/// どちらのフェーズのものか決まらなくなるため、隣と重ならない範囲でしか動かせない。
struct PhaseEditorView: View {
    @Bindable var phase: ObservationPhase

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ObservationTarget.createdAt) private var targets: [ObservationTarget]
    @State private var selectedTargetIDs: Set<PersistentIdentifier> = []
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now

    private var store: ObservationStore { ObservationStore(context: context) }

    private var selectableTypes: [PhaseType] {
        guard let plan = phase.plan else { return PhaseType.allCases }
        return store.selectablePhaseTypes(in: plan, editing: phase)
    }

    var body: some View {
        Form {
            Section {
                TextField("フェーズ名", text: $phase.name)
                Picker("種類", selection: $phase.type) {
                    ForEach(selectableTypes) { type in
                        Text(type.label).tag(type)
                    }
                }
            } header: {
                Text("フェーズ")
            } footer: {
                if !selectableTypes.contains(.baseline) {
                    Text("「\(PhaseType.baseline.label)」は比較の基準なので、プランに 1 つだけです。")
                }
            }

            Section {
                DatePicker(
                    "開始日",
                    selection: $startDate,
                    in: store.startDateRange(for: phase),
                    displayedComponents: .date
                )
                if store.canBeOngoing(phase) {
                    Toggle("終了日を設定", isOn: $hasEndDate)
                }
                if hasEndDate {
                    DatePicker(
                        "終了日",
                        selection: $endDate,
                        in: store.endDateRange(for: phase),
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("期間")
            } footer: {
                Text(periodFooter)
            }

            Section {
                Stepper(value: $phase.warmupDays, in: 0...14) {
                    HStack {
                        Text("集計から外す最初の日数")
                        Spacer(minLength: 8)
                        Text(phase.warmupDays == 0 ? "なし" : "\(phase.warmupDays)日")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("集計")
            } footer: {
                Text("始めてすぐは変化が出ないことがあります。外した日も記録は消えず、グラフにも点が出ます。平均と比較の集計からだけ外します。")
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
            startDate = Calendar.current.startOfDay(for: phase.startDate)
            hasEndDate = phase.endDate != nil
            endDate = phase.endDate ?? store.endDateRange(for: phase).upperBound
        }
        .onChange(of: selectedTargetIDs) { _, newValue in
            phase.targets = targets.matching(newValue)
        }
        .onChange(of: startDate) { _, newValue in
            store.moveStart(of: phase, to: newValue)
        }
        .onChange(of: hasEndDate) { _, newValue in
            store.setEnd(of: phase, to: newValue ? endDate : nil)
        }
        .onChange(of: endDate) { _, newValue in
            guard hasEndDate else { return }
            store.setEnd(of: phase, to: newValue)
        }
    }

    /// 期間の但し書き。効いている制限と、その場で起きる連鎖をその都度書く。
    private var periodFooter: String {
        var lines: [String] = []
        if let previous = store.previousPhase(of: phase) {
            lines.append("開始日を前に動かすと、「\(previous.name)」はその前日で終了します。記録は残ります。")
        }
        if store.canBeOngoing(phase) {
            if !hasEndDate {
                lines.append("終了日なしは「継続中」として扱われます。")
                lines.append("終了日を決めると、その日でこのフェーズは終わります。翌日からは次のフェーズを始めるまで、記録は残りますが期間ごとの平均や比較には入りません。")
            }
        } else {
            lines.append("次のフェーズがあるので、終了日は外せません。")
        }
        return lines.joined(separator: "\n")
    }
}
