import SwiftUI

/// 同じ観察対象を試した複数の期間で、記録の変化方向が繰り返されたかを見るカード。
/// 効果や因果関係の判定はせず、各回の数値と記録上の向きだけを並べる。
struct ReproducibilityCard: View {
    var checks: [ReproducibilityCheck]
    var metric: ObservationMetric

    var body: some View {
        SectionCard(title: "再現性チェック", systemImage: "arrow.triangle.2.circlepath") {
            if checks.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                        if index > 0 { Divider() }
                        checkContent(check)
                    }

                    Text("同じ観察対象でも、時期や生活など別の違いが含まれます。この表示だけで効果や因果関係は判断できません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("同じ条件をもう一度記録すると確認できます")
                .font(.system(.headline, design: .rounded))
            Text("同じ観察対象の組み合わせを持つ「試している期間」が2回以上あると、各回を直前の基準期間と自動で見くらべます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkContent(_ check: ReproducibilityCheck) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(check.title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text("同じ観察対象の組み合わせ \(check.phaseCount)回")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            resultPanel(check)

            if check.rounds.isEmpty {
                Text("直前の基準期間と見くらべられる記録がまだありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(ObservationTheme.raisedSurface.opacity(0.74), in: .rect(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(check.rounds.enumerated()), id: \.element.id) { index, round in
                        if index > 0 { Divider().padding(.leading, 38) }
                        roundRow(round, number: index + 1)
                    }
                }
                .background(ObservationTheme.raisedSurface.opacity(0.74), in: .rect(cornerRadius: 16))
            }

            if check.rounds.count < check.phaseCount {
                Text("基準期間または記録がない \(check.phaseCount - check.rounds.count)回は比較に含めていません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resultPanel(_ check: ReproducibilityCheck) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: resultSymbol(check))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(ObservationTheme.mint.opacity(0.24), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(resultHeadline(check))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(resultBasis(check))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ObservationTheme.mint.opacity(0.10), in: .rect(cornerRadius: 16))
    }

    private func roundRow(_ round: PhaseComparison, number: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 25, height: 25)
                .background(ObservationTheme.mint.opacity(0.22), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(round.subject.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("基準：\(round.reference.name) ・ \(round.subject.recordedDays)日 / \(round.reference.recordedDays)日")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            if let change = round.change(for: metric) {
                VStack(alignment: .trailing, spacing: 3) {
                    Label(
                        metric.formattedDelta(change.delta),
                        systemImage: symbol(for: change.recordedDirection)
                    )
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .labelStyle(.titleAndIcon)

                    if !round.meetsMinimum(for: metric) {
                        Text("日数不足")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("記録なし")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func resultHeadline(_ check: ReproducibilityCheck) -> String {
        guard let result = check.result(for: metric) else {
            return "再現性を確かめるには、比較できる記録が2回以上必要です"
        }
        guard let direction = result.dominantDirection else {
            return "比較ごとに、記録の変化方向が分かれています"
        }

        let subject = metric.averageTitle
        if direction == .unchanged {
            if result.matchingRounds == result.comparableRounds {
                return "記録上、\(result.comparableRounds)回とも\(subject)に大きな差はありませんでした"
            }
            return "記録上、\(result.comparableRounds)回のうち\(result.matchingRounds)回で\(subject)に大きな差はありませんでした"
        }

        let word = direction == .increase ? metric.comparativeWords.increase : metric.comparativeWords.decrease
        if result.matchingRounds == result.comparableRounds {
            return "記録上、\(result.comparableRounds)回とも\(subject)が\(word)なりました"
        }
        return "記録上、\(result.comparableRounds)回のうち\(result.matchingRounds)回で\(subject)が\(word)なりました"
    }

    private func resultBasis(_ check: ReproducibilityCheck) -> String {
        let comparableCount = check.comparableChanges(for: metric).count
        if comparableCount < 2 {
            return "各側に\(AnalysisBasis.minimumComparisonDays)日以上の記録がある比較を数えます。現在は\(comparableCount)回です。"
        }
        return "各回を、その直前に記録した「いつもの状態」または「お休み期間」と比較しています。"
    }

    private func resultSymbol(_ check: ReproducibilityCheck) -> String {
        guard let result = check.result(for: metric), let direction = result.dominantDirection else {
            return "arrow.left.arrow.right"
        }
        return symbol(for: direction)
    }

    private func symbol(for direction: RecordedChangeDirection) -> String {
        switch direction {
        case .increase: "arrow.up.right"
        case .decrease: "arrow.down.right"
        case .unchanged: "arrow.right"
        }
    }
}
