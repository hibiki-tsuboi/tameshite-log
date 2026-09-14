import SwiftUI

/// フェーズ 1 つ分の集計と、基準となる期間との比較。
struct PhaseSummaryCard: View {
    var summary: PhaseSummary
    var comparison: PhaseComparison?
    /// 同じフェーズの中で、観察対象を実施した日と実施しなかった日を見くらべたもの。
    var adherenceComparisons: [AdherenceComparison] = []
    var metric: ObservationMetric
    var color: Color

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                averages
                // 比較を実施の記録より先に置く。フェーズ単体の平均は、
                // 何と比べたかが分かって初めて読める数字で、この画面はそのためにある。
                // 実施の記録は日数を数え上げた表示で、比較ボックスが同じ日数を
                // 自分で書いているので、後ろに回しても読む順が壊れない。
                if let comparison {
                    Divider()
                    comparisonSection(comparison)
                }
                if !adherenceComparisons.isEmpty {
                    Divider()
                    adherenceComparisonSection
                }
                if !summary.adherence.isEmpty {
                    Divider()
                    adherenceSection
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

    // MARK: - 平均

    @ViewBuilder
    private var averages: some View {
        if summary.isFullyExcludedByWarmup {
            Text("最初の\(summary.warmupDays)日を集計から外す設定のため、まだ集計できる日がありません。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if summary.hasEnoughData {
            VStack(alignment: .leading, spacing: 12) {
                if let value = ObservationMetric.bowelCount.value(in: summary) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("平均排便回数")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(ObservationMetric.bowelCount.formatted(value))
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            if let spreadText = spreadText(for: .bowelCount) {
                                Text(spreadText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                HStack(alignment: .top, spacing: 12) {
                    ForEach([ObservationMetric.bristol, .abdominalPain, .urgency]) { metric in
                        StatTile(
                            title: metric.averageTitle,
                            value: metric.value(in: summary).map { metric.formatted($0) } ?? "—",
                            caption: spreadText(for: metric)
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

    // MARK: - 実施の記録

    private var adherenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("実施の記録")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(summary.adherence) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("実施 \(item.analyzedDays)日中\(item.completedDays)日")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                    }
                    if let detail = adherenceDetail(item) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            // 実施した日しか記録がないと、実施の有無での見くらべができない。
            // 数字を出さない代わりに、何を記録すれば見られるようになるかだけ書く。
            if adherenceComparisons.isEmpty, summary.adherence.contains(where: { $0.completedDays > 0 }) {
                Text("実施しなかった日も記録すると、同じ期間の中で実施した日と見くらべられます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func adherenceDetail(_ item: TargetAdherence) -> String? {
        var parts: [String] = []
        if item.skippedDays > 0 { parts.append("実施しなかった \(item.skippedDays)日") }
        if item.untrackedDays > 0 { parts.append("未記録 \(item.untrackedDays)日") }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }

    // MARK: - フェーズ同士の比較

    @ViewBuilder
    private func comparisonSection(_ comparison: PhaseComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(comparison.kind.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let change = comparison.change(for: metric) {
                changeBox(
                    change: change,
                    subjectName: summary.name,
                    subjectSpread: summary.spread(for: metric),
                    referenceName: comparison.reference.name,
                    referenceSpread: comparison.reference.spread(for: metric)
                )

                basisNote(
                    meetsMinimum: comparison.meetsMinimum(for: metric),
                    thinnerSideDays: comparison.thinnerSideDays(for: metric),
                    sentence: change.sentence(referenceName: comparison.reference.name)
                )
            } else {
                Text("比較できる記録がまだありません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 実施の有無による比較

    private var adherenceComparisonSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(adherenceComparisons) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text("「\(item.targetName)」実施した日と実施しなかった日")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let change = item.change(for: metric) {
                        changeBox(
                            change: change,
                            subjectName: "\(AdherenceComparison.completedLabel)（記録\(item.completedDays(for: metric))日）",
                            subjectSpread: nil,
                            referenceName: "\(AdherenceComparison.skippedLabel)（記録\(item.skippedDays(for: metric))日）",
                            referenceSpread: nil
                        )

                        basisNote(
                            meetsMinimum: item.meetsMinimum(for: metric),
                            thinnerSideDays: item.thinnerSideDays(for: metric),
                            sentence: change.sentence(referenceName: AdherenceComparison.skippedLabel)
                        )
                    } else {
                        Text("この指標では見くらべられる記録がありません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text("同じ期間の中での比較なので、期間ごとの違いは混ざっていません。どちらとも記録していない日は入れていません。かっこ内は、上の「実施の記録」で数えた日のうち、この指標の平均が出ている日数です。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 比較の共通パーツ

    private func changeBox(
        change: MetricChange,
        subjectName: String,
        subjectSpread: MetricSpread?,
        referenceName: String,
        referenceSpread: MetricSpread?
    ) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                comparisonValue(
                    name: subjectName,
                    value: metric.formatted(change.subject),
                    spread: subjectSpread,
                    emphasized: true
                )

                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                    .padding(8)
                    .background(color.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)

                comparisonValue(
                    name: referenceName,
                    value: metric.formatted(change.reference),
                    spread: referenceSpread,
                    emphasized: false
                )
            }

            Divider()

            HStack(spacing: 8) {
                resultPill(title: "差", value: metric.formattedDelta(change.delta))
                if let ratio = change.ratio {
                    resultPill(title: "変化", value: Formatting.signedPercent(ratio))
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [color.opacity(0.13), ObservationTheme.raisedSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(color.opacity(0.18), lineWidth: 1)
        }
    }

    private func comparisonValue(
        name: String,
        value: String,
        spread: MetricSpread?,
        emphasized: Bool
    ) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.caption.weight(emphasized ? .semibold : .regular))
                .foregroundStyle(emphasized ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 32, alignment: .bottom)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(emphasized ? color : .primary)
                .contentTransition(.numericText())
            if let spread, !spread.isFlat {
                Text("\(metric.formattedSpread(spread))の範囲")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func resultPill(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.bold)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(ObservationTheme.surface.opacity(0.8), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    /// 差を文章にしてよい日数がそろっていれば一文を、足りなければ何が足りないかを出す。
    ///
    /// 数値そのものは記録があれば出す。伏せると入力した本人が確かめられない。
    /// ただし「減っています」と言い切るには日数が要るので、その一文だけを差し替える。
    @ViewBuilder
    private func basisNote(meetsMinimum: Bool, thinnerSideDays: Int, sentence: String) -> some View {
        if meetsMinimum {
            Text(sentence)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label(
                "少ない側の記録が\(thinnerSideDays)日ぶんです。両方が\(AnalysisBasis.minimumComparisonDays)日ぶんそろうまでは、この差が日々のばらつきの範囲かどうか読み取れません。",
                systemImage: "exclamationmark.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: -

    /// 「1〜7回の範囲」。平均だけでは差が振れ幅の内か外か読めないので添える。
    private func spreadText(for metric: ObservationMetric) -> String? {
        guard let spread = summary.spread(for: metric), !spread.isFlat else { return nil }
        return "\(metric.formattedSpread(spread))の範囲"
    }

    private var periodDescription: String {
        var basis: [String] = []
        if summary.warmupDays > 0 { basis.append("最初の\(summary.warmupDays)日を除く") }
        if summary.warmupDays > 0 || summary.recordedDays < summary.analyzedDays {
            basis.append("記録 \(summary.recordedDays)日")
        }
        let detail = basis.isEmpty ? "" : "（\(basis.joined(separator: " ・ "))）"
        let range = Formatting.dateRange(from: summary.startDate, to: summary.endDate)
        return "\(summary.elapsedDays)日間\(detail) ・ \(range)"
    }
}
