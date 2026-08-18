import SwiftUI
import SwiftData

/// 新しいフェーズを始めるシート。
/// 開始日より前に始まっているフェーズは同時に閉じるので、期間が重ならない。
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

    private var store: ObservationStore { ObservationStore(context: context) }

    /// 選べる開始日の範囲。下限と上限の理由は `ObservationStore.newPhaseStartRange(in:asOf:)` に書いてある。
    private var startRange: ClosedRange<Date> { store.newPhaseStartRange(in: plan) }

    /// 開始日の順で最後のフェーズ。下限を決めているのはこのフェーズの開始日。
    private var latestPhase: ObservationPhase? { plan.orderedPhases.last }

    /// この開始によって短くなるフェーズ。選んだ日を含んでいるフェーズが前日で閉じられる。
    /// 継続中でも、閉じたフェーズの内側から始めた場合でも同じ扱いになる。
    private var shortenedPhase: ObservationPhase? { plan.phase(on: startDate) }

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
                    DatePicker("開始日", selection: $startDate, in: startRange, displayedComponents: .date)
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

                if shortenedPhase != nil || latestPhase != nil {
                    Section {
                        if let shortenedPhase {
                            Text("「\(shortenedPhase.name)」は開始日の前日で終了します。記録は残ります。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let latestPhase {
                            Text("開始日は「\(latestPhase.name)」の開始日より後の日から選べます。フェーズ同士が重ならないようにするためです。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
                // 最後のフェーズが今日始まっていると、既定の「今日」が下限を下回る。
                // 範囲外の値を持ったままだとピッカーの表示と実際の値が食い違う。
                startDate = min(max(startDate, startRange.lowerBound), startRange.upperBound)
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
