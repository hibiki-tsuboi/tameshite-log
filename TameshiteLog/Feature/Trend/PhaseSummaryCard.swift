import SwiftUI

/// フェーズ 1 つ分の集計と、基準となる期間との比較。
struct PhaseSummaryCard: View {
    var summary: PhaseSummary
    var comparison: PhaseComparison?
    var metric: ObservationMetric
    var color: Color

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                averages
                if let comparison {
                    Divider()
                    comparisonSection(comparison)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(summary.name)
                    .font(.system(.headline, design: .rounded))
                Spacer(minLength: 8)
                PhaseBadge(type: summary.type, color: color, phaseName: summary.name)
            }

            Text(periodDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if summary.targetSummary != "観察対象なし" {
                Label(summary.targetSummary, systemImage: "circle.dashed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var averages: some View {
        if summary.hasEnoughData {
            VStack(alignment: .leading, spacing: 12) {
                if let value = ObservationMetric.bowelCount.value(in: summary) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("平均排便回数")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(ObservationMetric.bowelCount.formatted(value))
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                    }
                    .accessibilityElement(children: .combine)
                }

                HStack(alignment: .top, spacing: 12) {
                    ForEach([ObservationMetric.bristol, .abdominalPain, .urgency]) { metric in
                        StatTile(
                            title: metric.averageTitle,
                            value: metric.value(in: summary).map { metric.formatted($0) } ?? "—"
                        )
                    }
                }
            }
        } else {
            Text("この期間にはまだ記録がありません。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func comparisonSection(_ comparison: PhaseComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(comparison.kind.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let change = comparison.change(for: metric) {
                VStack(spacing: 6) {
                    valueRow(name: summary.name, value: metric.formatted(change.subject), emphasized: true)
                    valueRow(name: comparison.reference.name, value: metric.formatted(change.reference), emphasized: false)

                    HStack {
                        Text("差")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(metric.formattedDelta(change.delta))
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Spacer()
                        if let ratio = change.ratio {
                            Text("変化")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(Formatting.signedPercent(ratio))
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        }
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))

                Text(change.sentence(referenceName: comparison.reference.name))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("比較できる記録がまだありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valueRow(name: String, value: String, emphasized: Bool) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(emphasized ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var periodDescription: String {
        let days = "\(summary.elapsedDays)日間"
        let recorded = summary.recordedDays < summary.elapsedDays ? "（記録 \(summary.recordedDays)日）" : ""
        let range = Formatting.dateRange(from: summary.startDate, to: summary.endDate)
        return "\(days)\(recorded) ・ \(range)"
    }
}
