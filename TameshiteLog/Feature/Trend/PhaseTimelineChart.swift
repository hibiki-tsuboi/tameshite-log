import SwiftUI
import Charts
import SwiftData

/// 日々の記録とフェーズの切り替わりを 1 枚に重ねたグラフ。
///
/// ・背景の帯   = フェーズの期間
/// ・破線の縦線 = フェーズの境目
/// ・破線の横線 = そのフェーズの平均
/// ・折れ線     = 1 日ごとの値
///
/// 記録がない日は点を打たない。0 として描くと「その日は 0 回だった」と読めてしまうため。
struct PhaseTimelineChart: View {
    var tallies: [DailyTally]
    var summaries: [PhaseSummary]
    var metric: ObservationMetric
    var color: (PhaseSummary) -> Color
    /// 書き出しのように「この期間だけ」を描きたいときの X 軸の範囲。nil ならデータに合わせる。
    var dateDomain: ClosedRange<Date>?
    var height: CGFloat = 240

    private var points: [DailyTally] {
        tallies.filter { metric.value(in: $0) != nil }
    }

    var body: some View {
        Chart {
            ForEach(summaries) { summary in
                let tint = color(summary)

                RectangleMark(
                    xStart: .value("開始", bandStart(summary)),
                    xEnd: .value("終了", bandEnd(summary))
                )
                .foregroundStyle(tint.opacity(0.10))
                .accessibilityHidden(true)

                if summary.id != summaries.first?.id {
                    RuleMark(x: .value("フェーズの境目", bandStart(summary)))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(tint.opacity(0.6))
                        .accessibilityHidden(true)
                }

                if let average = metric.value(in: summary) {
                    RuleMark(
                        xStart: .value("開始", bandStart(summary)),
                        xEnd: .value("終了", bandEnd(summary)),
                        y: .value(metric.averageTitle, average)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(tint)
                    .accessibilityLabel("\(summary.name)の\(metric.averageTitle)")
                    .accessibilityValue(metric.formatted(average))
                }
            }

            ForEach(points) { tally in
                if let value = metric.value(in: tally) {
                    LineMark(
                        x: .value("日付", tally.date),
                        y: .value(metric.title, value)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .accessibilityHidden(true)

                    PointMark(
                        x: .value("日付", tally.date),
                        y: .value(metric.title, value)
                    )
                    .symbolSize(28)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .accessibilityLabel(Formatting.shortDate(tally.date))
                    .accessibilityValue("\(metric.title) \(metric.formatted(value))")
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xStride)) { value in
                AxisGridLine()
                AxisTick()
                if let date = value.as(Date.self) {
                    AxisValueLabel(anchor: labelAnchor(for: date)) {
                        Text(Formatting.shortDate(date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxisLabel(alignment: .trailing) { Text("日付") }
        .chartYAxisLabel(alignment: .leading) { Text(metric.axisLabel) }
        .frame(height: height)
    }

    // 帯とグラフの点を揃えるため、日の前後に半日ずつ広げて日付の中心に点が来るようにする。
    private func bandStart(_ summary: PhaseSummary) -> Date {
        clamped(summary.startDate.addingTimeInterval(-43_200))
    }

    private func bandEnd(_ summary: PhaseSummary) -> Date {
        clamped(summary.effectiveEndDate.addingTimeInterval(43_200))
    }

    /// フェーズが表示範囲からはみ出していても、帯が軸を押し広げないように切り詰める。
    private func clamped(_ date: Date) -> Date {
        guard let dateDomain else { return date }
        return min(max(date, dateDomain.lowerBound), dateDomain.upperBound)
    }

    private var xDomain: ClosedRange<Date> {
        if let dateDomain { return dateDomain }
        let dates = tallies.map(\.date)
        guard let first = dates.first, let last = dates.last, first <= last else {
            let now = Date.now
            return now.addingTimeInterval(-43_200)...now.addingTimeInterval(43_200)
        }
        return first.addingTimeInterval(-43_200)...last.addingTimeInterval(43_200)
    }

    private var yDomain: ClosedRange<Double> {
        if let fixed = metric.axisDomain { return fixed }
        let maximum = points.compactMap { metric.value(in: $0) }.max() ?? 0
        return 0...max(4, (maximum + 1).rounded(.up))
    }

    /// 右端の目盛りは、ラベルがプロット領域からはみ出して切り詰められる。
    /// 端に近いものだけ内側に向けて書く。
    private func labelAnchor(for date: Date) -> UnitPoint {
        let span = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        guard span > 0 else { return .top }
        return xDomain.upperBound.timeIntervalSince(date) / span < 0.06 ? .topTrailing : .top
    }

    /// 目盛りが詰まりすぎないよう、期間の長さで間隔を決める。
    private var xStride: Int {
        let days = tallies.count
        return max(1, Int((Double(days) / 6).rounded(.up)))
    }
}
