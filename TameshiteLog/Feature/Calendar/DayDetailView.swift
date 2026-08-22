import SwiftUI
import SwiftData

/// カレンダーから開く 1 日分の詳細。あとから振り返って直せることを重視する。
struct DayDetailView: View {
    let day: Date

    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<ObservationPlan> { $0.isActive })
    private var activePlans: [ObservationPlan]

    @Query private var movements: [BowelMovement]

    @State private var isRecording = false
    @State private var editingMovement: BowelMovement?

    init(day: Date) {
        self.day = day
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _movements = Query(
            filter: #Predicate<BowelMovement> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\BowelMovement.recordedAt)]
        )
    }

    private var plan: ObservationPlan? { activePlans.first }
    private var phase: ObservationPhase? { plan?.phase(on: day) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                TargetChecklistCard(day: day, targets: phase?.orderedTargets ?? [])
                MovementListCard(
                    movements: movements,
                    onSelect: { editingMovement = $0 },
                    onDelete: { ObservationStore(context: context).delete($0) }
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
        .navigationTitle(Formatting.weekdayDate(day))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
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
        }
        .sheet(isPresented: $isRecording) {
            BowelMovementEditor(day: day)
        }
        .sheet(item: $editingMovement) { movement in
            BowelMovementEditor(day: day, movement: movement)
        }
    }

    private var header: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("排便 \(movements.count)回")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    Spacer(minLength: 8)
                    if let phase {
                        PhaseBadge(type: phase.type, color: phaseColor(phase), phaseName: phase.name)
                    }
                }

                if let phase {
                    Text(phase.name)
                        .font(.subheadline)
                    Text("\(Calendar.current.elapsedDayNumber(from: phase.startDate, to: day))日目 ・ \(Formatting.dateRange(from: phase.startDate, to: phase.endDate))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("この日を含むフェーズはありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            if movements.isEmpty {
                Divider()
                NoBowelMovementRow(day: day)
            }
        }
    }

    private func phaseColor(_ phase: ObservationPhase) -> Color {
        guard let plan else { return .accentColor }
        let index = plan.orderedPhases.firstIndex { $0.persistentModelID == phase.persistentModelID } ?? 0
        return PhasePalette.color(type: phase.type, index: index)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DayDetailView(day: .now)
    }
    .modelContainer(SampleData.previewContainer)
}
#endif
