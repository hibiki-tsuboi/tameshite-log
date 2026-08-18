import Foundation
import SwiftData

/// 記録からグラフ用・集計用の値を組み立てる。
///
/// SwiftData への問い合わせは呼び出し側が済ませ、ここは受け取った配列だけを見る。
/// 計算がビューにも永続化層にも依存しないので、そのままテストできる。
enum ObservationAnalyzer {

    // MARK: - 日別

    /// 指定期間の全日について、記録の有無を含めた 1 日分の集計を返す。
    /// 記録がない日も「記録なし」の要素として含めるため、グラフの歯抜けが表現できる。
    static func dailyTallies(
        movements: [BowelMovement],
        dailyRecords: [DailyRecord],
        in range: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> [DailyTally] {
        let movementsByDay = Dictionary(grouping: movements) { calendar.startOfDay(for: $0.date) }
        let recordsByDay = Dictionary(
            dailyRecords.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return calendar.days(from: range.lowerBound, through: range.upperBound).map { day in
            let dayMovements = movementsByDay[day] ?? []
            let summary = recordsByDay[day]
            return DailyTally(
                date: day,
                bowelCount: dayMovements.count,
                averageBristol: average(dayMovements.map { Double($0.bristolScale.rawValue) }),
                averagePain: average(dayMovements.map { Double($0.abdominalPain.rawValue) }),
                averageUrgency: average(dayMovements.map { Double($0.urgency.rawValue) }),
                overallCondition: summary?.overallCondition,
                abdominalCondition: summary?.abdominalCondition,
                hasSummary: summary.map { !$0.isEmpty } ?? false
            )
        }
    }

    // MARK: - フェーズ別

    static func summaries(
        for plan: ObservationPlan,
        movements: [BowelMovement],
        dailyRecords: [DailyRecord],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [PhaseSummary] {
        plan.orderedPhases.map { phase in
            summary(for: phase, movements: movements, dailyRecords: dailyRecords, today: today, calendar: calendar)
        }
    }

    static func summary(
        for phase: ObservationPhase,
        movements: [BowelMovement],
        dailyRecords: [DailyRecord],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> PhaseSummary {
        let start = calendar.startOfDay(for: phase.startDate)
        let end = phase.effectiveEndDate(asOf: today, calendar: calendar)

        let phaseMovements = movements.filter { phase.contains($0.date, calendar: calendar) && calendar.startOfDay(for: $0.date) <= end }
        let tallies = dailyTallies(
            movements: phaseMovements,
            dailyRecords: dailyRecords.filter { phase.contains($0.date, calendar: calendar) },
            in: start...max(start, end),
            calendar: calendar
        )
        let recordedDays = tallies.filter(\.hasRecord)

        // ブリストル値・腹痛・急な便意は、日ごとの平均ではなく記録 1 件ずつの平均を取る。
        // 排便回数が多い日と少ない日を同じ重みで扱わないため。
        return PhaseSummary(
            phaseID: phase.persistentModelID,
            name: phase.name,
            type: phase.type,
            startDate: start,
            endDate: phase.endDate,
            effectiveEndDate: end,
            targetSummary: phase.targetSummary,
            elapsedDays: calendar.dayCount(from: start, through: end),
            recordedDays: recordedDays.count,
            totalBowelCount: phaseMovements.count,
            averageBowelCount: average(recordedDays.map { Double($0.bowelCount) }),
            averageBristol: average(phaseMovements.map { Double($0.bristolScale.rawValue) }),
            averagePain: average(phaseMovements.map { Double($0.abdominalPain.rawValue) }),
            averageUrgency: average(phaseMovements.map { Double($0.urgency.rawValue) })
        )
    }

    // MARK: - 比較

    /// 各フェーズについて、ベースライン（なければ直前のフェーズ）との比較を作る。
    /// ベースライン自身と、比較先にデータがない場合は対象外。
    static func comparisons(for summaries: [PhaseSummary]) -> [PhaseComparison] {
        let baseline = summaries.first { $0.type == .baseline && $0.hasEnoughData }

        return summaries.enumerated().compactMap { index, summary in
            guard summary.hasEnoughData else { return nil }

            let previous = summaries[..<index].last { $0.hasEnoughData }
            let reference: PhaseSummary?
            let kind: PhaseComparison.Reference

            if let baseline, baseline.id != summary.id {
                reference = baseline
                kind = .baseline
            } else if let previous {
                reference = previous
                kind = .previous
            } else {
                reference = nil
                kind = .previous
            }

            guard let reference, reference.id != summary.id else { return nil }
            return comparison(subject: summary, reference: reference, kind: kind)
        }
    }

    /// ベースラインがあるフェーズでも、直前のフェーズとの比較を別途知りたい場合に使う。
    static func previousComparison(for summary: PhaseSummary, in summaries: [PhaseSummary]) -> PhaseComparison? {
        guard let index = summaries.firstIndex(where: { $0.id == summary.id }),
              let previous = summaries[..<index].last(where: \.hasEnoughData),
              summary.hasEnoughData else { return nil }
        return comparison(subject: summary, reference: previous, kind: .previous)
    }

    static func comparison(
        subject: PhaseSummary,
        reference: PhaseSummary,
        kind: PhaseComparison.Reference
    ) -> PhaseComparison {
        let changes = ObservationMetric.allCases.compactMap { metric -> MetricChange? in
            guard let subjectValue = metric.value(in: subject),
                  let referenceValue = metric.value(in: reference) else { return nil }
            return MetricChange(metric: metric, subject: subjectValue, reference: referenceValue)
        }
        return PhaseComparison(subject: subject, reference: reference, kind: kind, changes: changes)
    }

    // MARK: -

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
