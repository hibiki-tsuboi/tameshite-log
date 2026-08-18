import SwiftUI
import SwiftData

/// 観察プランの一覧。使うプランの切り替えもここで行う。
struct PlanListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ObservationPlan.createdAt, order: .reverse) private var plans: [ObservationPlan]
    @State private var isCreating = false

    var body: some View {
        List {
            if plans.isEmpty {
                ContentUnavailableView(
                    "プランがありません",
                    systemImage: "list.bullet.rectangle",
                    description: Text("「＋」から最初のプランを作成できます。")
                )
            }

            ForEach(plans) { plan in
                NavigationLink {
                    PlanEditorView(plan: plan)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(plan.name)
                            if plan.isActive {
                                Text("使用中")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.15), in: .capsule)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text("\(plan.phases.count)フェーズ ・ \(Formatting.mediumDate(plan.startDate))開始")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("削除", systemImage: "trash", role: .destructive) {
                        ObservationStore(context: context).delete(plan)
                    }
                }
                .swipeActions(edge: .leading) {
                    if !plan.isActive {
                        Button("使う", systemImage: "checkmark.circle") {
                            ObservationStore(context: context).activate(plan)
                        }
                        .tint(.accentColor)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("観察プラン")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("プランを追加", systemImage: "plus") { isCreating = true }
            }
        }
        .sheet(isPresented: $isCreating) {
            NavigationStack {
                PlanSetupView { isCreating = false }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { PlanListView() }
        .modelContainer(SampleData.previewContainer)
}
#endif
