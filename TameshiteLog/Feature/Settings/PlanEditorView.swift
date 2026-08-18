import SwiftUI
import SwiftData

/// プランの基本情報とフェーズの並びを編集する。
struct PlanEditorView: View {
    @Bindable var plan: ObservationPlan

    @Environment(\.modelContext) private var context
    @State private var isAddingPhase = false

    var body: some View {
        Form {
            Section("プラン") {
                TextField("プラン名", text: $plan.name)
                DatePicker("開始日", selection: $plan.startDate, displayedComponents: .date)
                if !plan.isActive {
                    Button("このプランを使う", systemImage: "checkmark.circle") {
                        ObservationStore(context: context).activate(plan)
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
                            ObservationStore(context: context).delete(phase)
                        }
                    }
                }
            } header: {
                Text("フェーズ")
            } footer: {
                Text("記録はフェーズに紐づけず日付で管理しています。期間を直すと集計もその場で合わせ直されます。")
            }

            Section {
                Button("フェーズを追加", systemImage: "plus") { isAddingPhase = true }
            }
        }
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
