import SwiftUI
import SwiftData

/// 今日の記録画面。アプリを開いて最初に見えるところ。
struct TodayView: View {
    @Query(filter: #Predicate<ObservationPlan> { $0.isActive })
    private var activePlans: [ObservationPlan]

    /// 「今日」は body の評価まかせにせず、状態として持つ。理由は `CurrentDayTracker` に書いてある。
    /// この画面は日付から記録先を決めているので、表示が前日なら記録も前日に入る。
    @State private var today = Date.now

    var body: some View {
        NavigationStack {
            if let plan = activePlans.first {
                TodayPlanView(plan: plan, day: today)
                    // 日付が変わったら作り直す。カードが持っている入力途中の状態が
                    // 新しい日に引き継がれず、前日ぶんの後片付けも走る。
                    .id(today)
            } else {
                NoActivePlanView()
                    .navigationTitle("今日")
            }
        }
        .tracksCurrentDay($today)
    }
}

/// 有効なプランがある場合の中身。
///
/// フェーズを動かす操作はツールバーではなくヘッダーカードに置く。この画面は 1 日に何度も
/// 開く記録画面で、主役は下の「排便を記録」。フェーズの開始や終了は数週間に一度の操作なので、
/// 画面唯一のツールバー枠を占めるほどの頻度がない。カードに寄せると、今のフェーズという
/// 状態表示と、それを変える操作が隣り合う。
private struct TodayPlanView: View {
    let plan: ObservationPlan
    let day: Date

    @Environment(\.modelContext) private var context
    @Query private var movements: [BowelMovement]

    @State private var isRecording = false
    @State private var editingMovement: BowelMovement?
    @State private var isStartingPhase = false

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

    private var store: ObservationStore { ObservationStore(context: context) }

    private var currentPhase: ObservationPhase? { plan.phase(on: day) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                TargetChecklistCard(title: "今日の観察対象", day: day, targets: currentPhase?.orderedTargets ?? [])
                countCard
                MovementListCard(
                    title: "今日の記録",
                    movements: movements,
                    onSelect: { editingMovement = $0 },
                    onDelete: { store.delete($0) }
                )
                DailySummaryCard(day: day)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .readableWidth()
            .dismissesKeyboardOnBackgroundTap()
        }
        // 指で下ろしても閉じる。こちらが iOS の標準ジェスチャで、余白タップは補いになる。
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle("今日")
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
    }

    // MARK: - 各パーツ

    private var header: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Formatting.weekdayDate(day))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(plan.name)
                        .font(.headline)
                }
                .accessibilityElement(children: .combine)

                if let phase = currentPhase {
                    phaseLink(phase)
                } else {
                    noPhaseNotice
                }

                Divider()
                startPhaseButton
            }
        }
    }

    /// 今のフェーズ。表示そのものを編集への入口にして、状態と操作を離さない。
    /// 期間を直すのも、このフェーズを終えるのも、この先の `PhaseEditorView` で行う。
    private func phaseLink(_ phase: ObservationPhase) -> some View {
        NavigationLink {
            PhaseEditorView(phase: phase)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityHint("フェーズの期間や内容を編集します")
        }
        .buttonStyle(.plain)
    }

    /// フェーズのない日でも記録は止めない。代わりに、このままだと集計に入らないことと、
    /// さかのぼれば拾えることを書いておく。
    private var noPhaseNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日を含むフェーズがありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("記録はこのまま続けられますが、期間ごとの平均や比較には入りません。開始日をさかのぼってフェーズを始めれば、その期間の記録もまとめて入ります。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// フェーズを始める入口。フェーズの有無で文言を変えない。
    /// 始めた日より前に始まっているフェーズは `startPhase` が前日で閉じるので、
    /// 「終えてから始める」と「そのまま次を始める」を選ばせる必要はない。
    private var startPhaseButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("フェーズを始める", systemImage: "plus") { isStartingPhase = true }
                .font(.subheadline)
                .disabled(startBlockedReason != nil)

            if let startBlockedReason {
                Text(startBlockedReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 今日は始められない理由。始められるなら `nil`。
    ///
    /// 今日フェーズを始めたばかりだと `newPhaseStartRange(in:asOf:)` の下限が明日になり、
    /// 選べる日が明日だけに潰れる。押せるままにすると未来から始まるフェーズができるので、
    /// 押せなくしたうえで、いま何ができるのかを書く。
    ///
    /// 判定は `PhaseStartSheet` が範囲を作るときと同じ「今日」基準にする。表示中の日を
    /// 基準にすると、押せるのにシート側では選べる日がない、という食い違いが出る。
    private var startBlockedReason: String? {
        guard !store.canStartNewPhase(in: plan), let latest = plan.orderedPhases.last else { return nil }
        return "次のフェーズは「\(latest.name)」の開始日より後の日から始められます。"
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
        .appBackground()
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
