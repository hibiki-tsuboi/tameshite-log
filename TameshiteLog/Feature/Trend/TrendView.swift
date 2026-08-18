import SwiftUI
import SwiftData

/// 経過画面。このアプリの中心となる分析画面。
///
/// 表示するのは記録から計算した数値と、その差だけ。
/// 効いている・合っているといった判断は書かない。
struct TrendView: View {
    @Query(filter: #Predicate<ObservationPlan> { $0.isActive })
    private var activePlans: [ObservationPlan]

    @Query(sort: \BowelMovement.date) private var movements: [BowelMovement]
    @Query(sort: \DailyRecord.date) private var dailyRecords: [DailyRecord]

    @State private var metric: ObservationMetric = .bowelCount

    private var plan: ObservationPlan? { activePlans.first }

    var body: some View {
        NavigationStack {
            Group {
                if let plan, let range = plan.observedRange() {
                    content(plan: plan, range: range)
                } else {
                    ContentUnavailableView(
                        "まだ経過がありません",
                        systemImage: "chart.xyaxis.line",
                        description: Text("観察プランを作り、数日ぶん記録すると変化を振り返れます。")
                    )
                }
            }
            .navigationTitle("経過")
        }
    }

    private func content(plan: ObservationPlan, range: ClosedRange<Date>) -> some View {
        let tallies = ObservationAnalyzer.dailyTallies(
            movements: movements,
            dailyRecords: dailyRecords,
            in: range
        )
        let summaries = ObservationAnalyzer.summaries(
            for: plan,
            movements: movements,
            dailyRecords: dailyRecords
        )
        let comparisons = ObservationAnalyzer.comparisons(for: summaries)
        let colors = colorMap(for: plan, summaries: summaries)

        return ScrollView {
            VStack(spacing: 16) {
                Picker("指標", selection: $metric) {
                    ForEach(ObservationMetric.allCases) { metric in
                        Text(metric.shortTitle).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                SectionCard(title: metric.title, systemImage: "chart.xyaxis.line") {
                    if tallies.contains(where: { metric.value(in: $0) != nil }) {
                        PhaseTimelineChart(
                            tallies: tallies,
                            summaries: summaries,
                            metric: metric,
                            color: { colors[$0.id] ?? .accentColor }
                        )
                        Text("背景の色分けはフェーズ、破線はそのフェーズの平均です。記録のない日は点を打っていません。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("この指標の記録がまだありません。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }

                ForEach(summaries) { summary in
                    PhaseSummaryCard(
                        summary: summary,
                        comparison: comparisons.first { $0.subject.id == summary.id },
                        metric: metric,
                        color: colors[summary.id] ?? .accentColor
                    )
                }

                disclaimer
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .readableWidth()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var disclaimer: some View {
        Text("表示しているのは記録から計算した数値です。服薬や症状については医師・薬剤師にご相談ください。")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    /// グラフの帯と集計カードで同じ色を使うための対応表。
    private func colorMap(for plan: ObservationPlan, summaries: [PhaseSummary]) -> [PersistentIdentifier: Color] {
        summaries.enumerated().reduce(into: [:]) { result, item in
            result[item.element.id] = PhasePalette.color(type: item.element.type, index: item.offset)
        }
    }
}

#if DEBUG
#Preview {
    TrendView()
        .modelContainer(SampleData.previewContainer)
}
#endif
