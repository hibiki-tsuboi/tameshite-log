import SwiftUI
import SwiftData

/// 新しいフェーズを始めるシート。
/// 開始と同時に継続中のフェーズを閉じるので、期間が重ならない。
struct PhaseStartSheet: View {
    let plan: ObservationPlan

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: PhaseType = .intervention
    @State private var startDate = Date.now
    @State private var selectedTargetIDs: Set<PersistentIdentifier> = []
    @State private var note = ""
    @State private var warmupDays = 0

    @Query(sort: \ObservationTarget.createdAt) private var targets: [ObservationTarget]

    private var ongoingPhase: ObservationPhase? {
        plan.orderedPhases.last { $0.isOngoing }
    }

    /// 選べる開始日の下限。継続中のフェーズがあるときは、その翌日以降に限る。
    ///
    /// 同じ日や前の日を選べてしまうと、継続中のフェーズを「開始日の前日」で閉じられない。
    /// 下のフッタで約束していることが守れなくなるので、選べないようにしておく。
    ///
    /// 継続中のフェーズがないときは下限を設けない。フェーズのない期間をあとから
    /// さかのぼって拾う使い方（今日画面が案内している）を止めないため。
    private var earliestStartDate: Date? {
        guard let ongoingPhase else { return nil }
        let start = Calendar.current.startOfDay(for: ongoingPhase.startDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("フェーズ名", text: $name)
                        .textInputAutocapitalization(.never)
                    Picker("種類", selection: $type) {
                        ForEach(PhaseType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    if let earliestStartDate {
                        DatePicker(
                            "開始日",
                            selection: $startDate,
                            in: earliestStartDate...,
                            displayedComponents: .date
                        )
                    } else {
                        DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                    }
                } header: {
                    Text("新しいフェーズ")
                } footer: {
                    Text(type.detail)
                }

                Section {
                    Stepper(value: $warmupDays, in: 0...14) {
                        HStack {
                            Text("集計から外す最初の日数")
                            Spacer(minLength: 8)
                            Text(warmupDays == 0 ? "なし" : "\(warmupDays)日")
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
                    TextField("任意", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let ongoing = ongoingPhase {
                    Section {
                        Text("「\(ongoing.name)」は開始日の前日で終了します。記録は残ります。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("開始日は「\(ongoing.name)」の開始日より後の日から選べます。期間が重ならないようにするためです。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("フェーズを始める")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("開始") { start() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // 継続中のフェーズが今日始まっていると、既定の「今日」が下限を下回る。
                // 範囲外の値を持ったままだとピッカーの表示と実際の値が食い違う。
                if let earliestStartDate, startDate < earliestStartDate {
                    startDate = earliestStartDate
                }
            }
            .onChange(of: type) { _, newValue in
                // 種類を選んだだけで名前が埋まると、そのまま保存できて速い。
                if name.isEmpty || PhaseType.allCases.map(\.label).contains(name) {
                    name = newValue.label
                }
            }
        }
    }

    private func start() {
        let store = ObservationStore(context: context)
        store.startPhase(
            name: name.trimmingCharacters(in: .whitespaces),
            type: type,
            targets: targets.matching(selectedTargetIDs),
            on: startDate,
            in: plan,
            note: note,
            warmupDays: warmupDays
        )
        dismiss()
    }
}

#if DEBUG
#Preview {
    PhaseStartSheet(plan: SampleData.previewPlan)
        .modelContainer(SampleData.previewContainer)
}
#endif
