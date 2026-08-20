import SwiftUI
import SwiftData

/// プランの基本情報とフェーズの並びを編集する。
struct PlanEditorView: View {
    @Bindable var plan: ObservationPlan

    @Environment(\.modelContext) private var context
    @State private var isAddingPhase = false

    private var store: ObservationStore { ObservationStore(context: context) }

    /// 今日はフェーズを始められない理由。始められるなら `nil`。
    /// 潰れた範囲のまま開始させない理由は `ObservationStore.canStartNewPhase(in:asOf:)` に書いてある。
    private var startBlockedReason: String? {
        guard !store.canStartNewPhase(in: plan), let latest = plan.orderedPhases.last else { return nil }
        return "次のフェーズは「\(latest.name)」の開始日より後の日から始められます。"
    }

    var body: some View {
        Form {
            Section("プラン") {
                TextField("プラン名", text: $plan.name)
                DatePicker("開始日", selection: $plan.startDate, displayedComponents: .date)
                if !plan.isActive {
                    Button("このプランを使う", systemImage: "checkmark.circle") {
                        store.activate(plan)
                    }
                }
            }

            Section {
                if plan.orderedPhases.isEmpty {
                    Text("フェーズがありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(plan.orderedPhases.enumerated()), id: \.element.persistentModelID) { index, phase in
                    NavigationLink {
                        PhaseEditorView(phase: phase)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PhasePalette.color(type: phase.type, index: index))
                                .frame(width: 4, height: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(phase.name)
                                Text("\(phase.type.label) ・ \(Formatting.dateRange(from: phase.startDate, to: phase.endDate))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !phase.targets.isEmpty {
                                    Text(phase.targetSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("削除", systemImage: "trash", role: .destructive) {
                            store.delete(phase)
                        }
                    }
                }
            } header: {
                Text("フェーズ")
            } footer: {
                Text("記録はフェーズに紐づけず日付で管理しています。期間を直すと集計もその場で合わせ直されます。")
            }

            Section {
                Button("フェーズを始める", systemImage: "plus") { isAddingPhase = true }
                    .disabled(startBlockedReason != nil)
            } footer: {
                if let startBlockedReason {
                    Text(startBlockedReason)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        // 既定はスクロールで即閉じる。指の動きに追従させて、他の画面と揃える。
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("プランの編集")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddingPhase) {
            PhaseStartSheet(plan: plan)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PlanEditorView(plan: SampleData.previewPlan)
    }
    .modelContainer(SampleData.previewContainer)
}
#endif
