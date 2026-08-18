import SwiftUI
import SwiftData

/// 今日の記録画面。アプリを開いて最初に見えるところ。
struct TodayView: View {
    @Query(filter: #Predicate<ObservationPlan> { $0.isActive })
    private var activePlans: [ObservationPlan]

    var body: some View {
        NavigationStack {
            if let plan = activePlans.first {
                TodayPlanView(plan: plan, day: .now)
            } else {
                NoActivePlanView()
                    .navigationTitle("今日")
            }
        }
    }
}

/// 有効なプランがある場合の中身。
private struct TodayPlanView: View {
    let plan: ObservationPlan
    let day: Date

    @Environment(\.modelContext) private var context
    @Query private var movements: [BowelMovement]

    @State private var isRecording = false
    @State private var editingMovement: BowelMovement?
    @State private var isStartingPhase = false
    @State private var isConfirmingPhaseEnd = false

    init(plan: ObservationPlan, day: Date) {
        self.plan = plan
        self.day = day
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _movements = Query(
            filter: #Predicate<BowelMovement> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\BowelMovement.recordedAt)]
        )
    }

    private var currentPhase: ObservationPhase? { plan.phase(on: day) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                countCard
                MovementListCard(
                    title: "今日の記録",
                    movements: movements,
                    onSelect: { editingMovement = $0 },
                    onDelete: { ObservationStore(context: context).delete($0) }
                )
                TargetChecklistCard(title: "今日の観察対象", day: day, targets: currentPhase?.targets ?? [])
                DailySummaryCard(day: day)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .readableWidth()
        }
        .appBackground()
        .navigationTitle("今日")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("次のフェーズを始める", systemImage: "arrow.turn.down.right") {
                        isStartingPhase = true
                    }
                    if let phase = currentPhase, phase.isOngoing {
                        Button("このフェーズを今日で終える", systemImage: "stop.circle") {
                            isConfirmingPhaseEnd = true
                        }
                    }
                } label: {
                    Label("フェーズ", systemImage: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { recordButton }
        .sheet(isPresented: $isRecording) {
            BowelMovementEditor(day: day)
        }
        .sheet(item: $editingMovement) { movement in
            BowelMovementEditor(day: day, movement: movement)
        }
        .sheet(isPresented: $isStartingPhase) {
            PhaseStartSheet(plan: plan)
        }
        .confirmationDialog(
            "このフェーズを今日で終えますか？",
            isPresented: $isConfirmingPhaseEnd,
            titleVisibility: .visible
        ) {
            Button("今日で終える") {
                if let phase = currentPhase {
                    ObservationStore(context: context).endPhase(phase, on: day)
                }
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("記録はそのまま残ります。ただし明日からは、次のフェーズを始めるまで期間ごとの平均や比較に入りません。期間はあとから変えられます。")
        }
    }

    // MARK: - 各パーツ

    private var header: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(Formatting.weekdayDate(day))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(plan.name)
                    .font(.headline)

                if let phase = currentPhase {
                    HStack(alignment: .firstTextBaseline) {
                        Text(phase.name)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Spacer(minLength: 8)
                        PhaseBadge(type: phase.type, color: phaseColor(phase), phaseName: phase.name)
                    }

                    Text("\(Calendar.current.elapsedDayNumber(from: phase.startDate, to: day))日目 ・ \(Formatting.dateRange(from: phase.startDate, to: phase.endDate))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !phase.targets.isEmpty {
                        Text(phase.targetSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // フェーズのない日でも記録は止めない。代わりに、このままだと
                    // 集計に入らないことと、さかのぼれば拾えることを書いておく。
                    Text("今日を含むフェーズがありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("記録はこのまま続けられますが、期間ごとの平均や比較には入りません。開始日をさかのぼってフェーズを始めれば、その期間の記録もまとめて入ります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("フェーズを始める") { isStartingPhase = true }
                        .font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var countCard: some View {
        SectionCard(title: "今日の排便", systemImage: "chart.bar") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(movements.count)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("回")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("今日の排便回数 \(movements.count)回")

            if movements.isEmpty {
                Divider()
                NoBowelMovementRow(day: day)
            } else {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    StatTile(title: "平均ブリストル", value: Formatting.decimal(average(\.bristolScale.rawValue)))
                    StatTile(title: "腹痛 平均", value: Formatting.decimal(average(\.abdominalPain.rawValue)))
                    StatTile(title: "急な便意 平均", value: Formatting.decimal(average(\.urgency.rawValue)))
                }
            }
        }
    }

    private var recordButton: some View {
        Button {
            isRecording = true
        } label: {
            Label("排便を記録", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .readableWidth()
        .accessibilityHint("便の状態を選んで保存します")
    }

    private func average(_ keyPath: KeyPath<BowelMovement, Int>) -> Double {
        guard !movements.isEmpty else { return 0 }
        return movements.reduce(0.0) { $0 + Double($1[keyPath: keyPath]) } / Double(movements.count)
    }

    private func phaseColor(_ phase: ObservationPhase) -> Color {
        let index = plan.orderedPhases.firstIndex { $0.persistentModelID == phase.persistentModelID } ?? 0
        return PhasePalette.color(type: phase.type, index: index)
    }
}

/// プランが 1 つもない、または有効なプランがないときの案内。
struct NoActivePlanView: View {
    @State private var isCreatingPlan = false

    var body: some View {
        ContentUnavailableView {
            Label("観察プランがありません", systemImage: "list.bullet.rectangle")
        } description: {
            Text("何かを試す前後の変化を振り返るには、まず観察プランを作ります。")
        } actions: {
            Button("観察をはじめる") { isCreatingPlan = true }
                .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $isCreatingPlan) {
            NavigationStack {
                PlanSetupView { isCreatingPlan = false }
            }
        }
    }
}

#if DEBUG
#Preview("記録あり") {
    TodayView()
        .modelContainer(SampleData.previewContainer)
}

#Preview("プランなし") {
    TodayView()
        .modelContainer(SampleData.emptyPreviewContainer)
}
#endif
