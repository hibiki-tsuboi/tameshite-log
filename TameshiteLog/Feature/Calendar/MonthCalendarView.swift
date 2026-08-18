import SwiftUI
import SwiftData

/// 月間カレンダー。記録の有無・排便回数・フェーズが一目で分かることを狙う。
struct MonthCalendarView: View {
    @Query(filter: #Predicate<ObservationPlan> { $0.isActive })
    private var activePlans: [ObservationPlan]

    @Query private var movements: [BowelMovement]
    @Query private var dailyRecords: [DailyRecord]

    @State private var month: Date = Calendar.current.startOfMonth(for: .now)

    private let calendar = Calendar.current
    private var plan: ObservationPlan? { activePlans.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayHeader
                    grid
                    legend
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("カレンダー")
            .navigationDestination(for: Date.self) { day in
                DayDetailView(day: day)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("今月", systemImage: "arrow.uturn.backward") {
                        withAnimation { month = calendar.startOfMonth(for: .now) }
                    }
                    .disabled(calendar.isDate(month, equalTo: .now, toGranularity: .month))
                }
            }
        }
    }

    // MARK: - パーツ

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation { shiftMonth(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("前の月")

            Spacer()
            Text(month.formatted(.dateTime.year().month()))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())
            Spacer()

            Button {
                withAnimation { shiftMonth(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("次の月")
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(calendar.orderedShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        let days = calendar.monthGridDays(for: month)
        let countsByDay = Dictionary(grouping: movements) { calendar.startOfDay(for: $0.date) }
            .mapValues(\.count)
        let summaryDays = Set(dailyRecords.filter { !$0.isEmpty }.map { calendar.startOfDay(for: $0.date) })

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(days, id: \.self) { day in
                NavigationLink(value: day) {
                    DayCell(
                        day: day,
                        isInDisplayedMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                        isToday: calendar.isDateInToday(day),
                        bowelCount: countsByDay[day] ?? 0,
                        hasSummary: summaryDays.contains(day),
                        phaseColor: phaseColor(on: day)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var legend: some View {
        if let plan, !plan.orderedPhases.isEmpty {
            SectionCard(title: "フェーズ", systemImage: "square.stack.3d.up") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(plan.orderedPhases.enumerated()), id: \.element.persistentModelID) { index, phase in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PhasePalette.color(type: phase.type, index: index))
                                .frame(width: 14, height: 4)
                            Text(phase.name)
                                .font(.subheadline)
                            Spacer(minLength: 8)
                            Text(Formatting.dateRange(from: phase.startDate, to: phase.endDate))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: -

    private func shiftMonth(by value: Int) {
        month = calendar.date(byAdding: .month, value: value, to: month) ?? month
    }

    /// 継続中のフェーズは終了日を持たないので、そのままだと未来の日まで色が付いてしまう。
    /// まだ来ていない日は「そのフェーズだった」とは言えないため、今日で打ち切る。
    private func phaseColor(on day: Date) -> Color? {
        guard let plan, day <= calendar.startOfDay(for: .now) else { return nil }
        let phases = plan.orderedPhases
        guard let index = phases.lastIndex(where: { $0.contains(day, calendar: calendar) }) else { return nil }
        return PhasePalette.color(type: phases[index].type, index: index)
    }
}

/// カレンダーの 1 マス。
private struct DayCell: View {
    var day: Date
    var isInDisplayedMonth: Bool
    var isToday: Bool
    var bowelCount: Int
    var hasSummary: Bool
    var phaseColor: Color?

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: day))"
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(dayNumber)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? Color.white : (isInDisplayedMonth ? Color.primary : Color.secondary.opacity(0.5)))
                .frame(width: 26, height: 26)
                .background {
                    if isToday { Circle().fill(Color.accentColor) }
                }

            if bowelCount > 0 {
                Text("\(bowelCount)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if hasSummary {
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 4, height: 4)
            } else {
                Color.clear.frame(height: 12)
            }

            RoundedRectangle(cornerRadius: 1.5)
                .fill(phaseColor ?? .clear)
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 10))
        .opacity(isInDisplayedMonth ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = [Formatting.weekdayDate(day)]
        if isToday { parts.append("今日") }
        parts.append(bowelCount > 0 ? "排便\(bowelCount)回" : (hasSummary ? "まとめあり" : "記録なし"))
        return parts.joined(separator: "、")
    }
}

#if DEBUG
#Preview {
    MonthCalendarView()
        .modelContainer(SampleData.previewContainer)
}
#endif
