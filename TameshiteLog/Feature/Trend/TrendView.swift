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
    @Query(sort: \TargetRecord.date) private var targetRecords: [TargetRecord]

    @State private var metric: ObservationMetric = .bowelCount
    @State private var isExporting = false

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
            .appBackground()
            .navigationTitle("経過")
            .toolbar {
                if plan != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("書き出す", systemImage: "square.and.arrow.up") { isExporting = true }
                    }
                }
            }
            .sheet(isPresented: $isExporting) {
                NavigationStack {
                    ExportView(initialPlan: plan)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") { isExporting = false }
                            }
                        }
                }
            }
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
            dailyRecords: dailyRecords,
            targetRecords: targetRecords
        )
        let comparisons = ObservationAnalyzer.comparisons(for: summaries)
        let adherenceComparisons = Dictionary(
            grouping: ObservationAnalyzer.adherenceComparisons(
                for: plan,
                movements: movements,
                dailyRecords: dailyRecords,
                targetRecords: targetRecords
            ),
            by: \.phaseID
        )
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
                        Text(chartNote(summaries: summaries))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                        adherenceComparisons: adherenceComparisons[summary.id] ?? [],
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
    }

    /// 立ち上がりを外しているフェーズがあるときだけ、点と平均のずれについて足す。
    /// 外した日も点は出ているので、平均の破線と合わないように見える。
    private func chartNote(summaries: [PhaseSummary]) -> String {
        var note = "背景の色分けはフェーズ、破線はそのフェーズの平均です。記録のない日は点を打っていません。"
        if summaries.contains(where: { $0.warmupDays > 0 }) {
            note += "集計から外した開始直後の日も、記録として点は表示しています。"
        }
        return note
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
