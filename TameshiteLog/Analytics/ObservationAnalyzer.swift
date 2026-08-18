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
                hasSummary: summary.map { !$0.isEmpty } ?? false,
                hadNoBowelMovement: summary?.hadNoBowelMovement ?? false
            )
        }
    }

    // MARK: - フェーズ別

    static func summaries(
        for plan: ObservationPlan,
        movements: [BowelMovement],
        dailyRecords: [DailyRecord],
        targetRecords: [TargetRecord],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [PhaseSummary] {
        plan.orderedPhases.map { phase in
            summary(
                for: phase,
                movements: movements,
                dailyRecords: dailyRecords,
                targetRecords: targetRecords,
                today: today,
                calendar: calendar
            )
        }
    }

    static func summary(
        for phase: ObservationPhase,
        movements: [BowelMovement],
        dailyRecords: [DailyRecord],
        targetRecords: [TargetRecord],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> PhaseSummary {
        let window = analysisWindow(for: phase, today: today, calendar: calendar)

        let windowMovements = movements.filter { window.contains($0.date, calendar: calendar) }
        let windowRecords = dailyRecords.filter { window.contains($0.date, calendar: calendar) }
        let tallies = window.range.map {
            dailyTallies(movements: windowMovements, dailyRecords: windowRecords, in: $0, calendar: calendar)
        } ?? []
        let recorded = tallies.filter(\.hasRecord)
        let values = metricValues(recordedTallies: recorded, movements: windowMovements)

        return PhaseSummary(
            phaseID: phase.persistentModelID,
            name: phase.name,
            type: phase.type,
            startDate: window.phaseStart,
            endDate: phase.endDate,
            effectiveEndDate: window.end,
            targetSummary: phase.targetSummary,
            elapsedDays: window.elapsedDays,
            recordedDays: recorded.count,
            warmupDays: phase.warmupDays,
            analyzedDays: window.analyzedDays,
            totalBowelCount: windowMovements.count,
            averageBowelCount: values.average(.bowelCount),
            averageBristol: values.average(.bristol),
            averagePain: values.average(.abdominalPain),
            averageUrgency: values.average(.urgency),
            spreads: values.spreads,
            adherence: adherence(for: phase, targetRecords: targetRecords, window: window, calendar: calendar)
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

    // MARK: - 実施の有無による比較

    /// プランの全フェーズについて、実施した日と実施しなかった日の比較を集める。
    static func adherenceComparisons(
        for plan: ObservationPlan,
        movements: [BowelMovement],
        dailyRecords: [DailyRecord],
        targetRecords: [TargetRecord],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [AdherenceComparison] {
        plan.orderedPhases.flatMap { phase in
            adherenceComparisons(
                for: phase,
                movements: movements,
                dailyRecords: dailyRecords,
                targetRecords: targetRecords,
                today: today,
                calendar: calendar
            )
        }
    }

    /// 同じフェーズの中で、観察対象を実施した日と実施しなかった日を見くらべる。
    ///
    /// フェーズ同士の比較と違い期間が同じなので、季節や生活の変化が混ざりこまない。
    /// どちらとも記録されていない日はどちらの側にも入れない。飲み忘れを 0 と数えるのと
    /// 同じ間違いになるため。両側に記録がある対象だけを返す。
    static func adherenceComparisons(
        for phase: ObservationPhase,
        movements: [BowelMovement],
        dailyRecords: [DailyRecord],
        targetRecords: [TargetRecord],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> [AdherenceComparison] {
        let window = analysisWindow(for: phase, today: today, calendar: calendar)
        guard let range = window.range else { return [] }

        let windowMovements = movements.filter { window.contains($0.date, calendar: calendar) }
        let windowRecords = dailyRecords.filter { window.contains($0.date, calendar: calendar) }
        let talliesByDay = Dictionary(
            dailyTallies(movements: windowMovements, dailyRecords: windowRecords, in: range, calendar: calendar)
                .map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return phase.targets.compactMap { target in
            let marked = markedDays(for: target, in: targetRecords, window: window, calendar: calendar)

            /// 片側ぶんの集計。分母は「その側の日のうち記録が付いた日数」。
            func side(_ days: Set<Date>) -> (recordedDays: Int, values: MetricValues) {
                let recorded = days.compactMap { talliesByDay[$0] }.filter(\.hasRecord)
                let sideMovements = windowMovements.filter { days.contains(calendar.startOfDay(for: $0.date)) }
                return (recorded.count, metricValues(recordedTallies: recorded, movements: sideMovements))
            }

            let completed = side(marked.completed)
            let skipped = side(marked.skipped)
            guard completed.recordedDays > 0, skipped.recordedDays > 0 else { return nil }

            let changes = ObservationMetric.allCases.compactMap { metric -> MetricChange? in
                guard let subject = completed.values.average(metric),
                      let reference = skipped.values.average(metric) else { return nil }
                return MetricChange(metric: metric, subject: subject, reference: reference)
            }
            guard !changes.isEmpty else { return nil }

            return AdherenceComparison(
                phaseID: phase.persistentModelID,
                targetID: target.persistentModelID,
                targetName: target.name,
                completedDays: completed.recordedDays,
                skippedDays: skipped.recordedDays,
                changes: changes
            )
        }
    }

    // MARK: - 集計の窓

    /// フェーズの集計に使う日付の範囲。
    ///
    /// 開始日は `warmupDays` のぶん後ろへずらすが、フェーズの長さ（`elapsedDays`）は
    /// 実際の開始日から数える。「30日間のうち最初の3日を外して集計した」と書けるようにするため。
    private struct AnalysisWindow {
        var phaseStart: Date
        var start: Date
        var end: Date
        var elapsedDays: Int
        var analyzedDays: Int

        /// 立ち上がりの除外が期間全体を飲み込むと空になる。
        var range: ClosedRange<Date>? { start <= end ? start...end : nil }

        func contains(_ date: Date, calendar: Calendar) -> Bool {
            let day = calendar.startOfDay(for: date)
            return day >= start && day <= end
        }
    }

    private static func analysisWindow(
        for phase: ObservationPhase,
        today: Date,
        calendar: Calendar
    ) -> AnalysisWindow {
        let phaseStart = calendar.startOfDay(for: phase.startDate)
        let end = phase.effectiveEndDate(asOf: today, calendar: calendar)
        let start = phase.analysisStartDate(calendar: calendar)
        return AnalysisWindow(
            phaseStart: phaseStart,
            start: start,
            end: end,
            elapsedDays: calendar.dayCount(from: phaseStart, through: end),
            analyzedDays: calendar.dayCount(from: start, through: end)
        )
    }

    // MARK: - 指標

    /// 指標ごとの平均とばらつき。フェーズ全体にも、フェーズ内の一部の日にも同じ計算を通す。
    private struct MetricValues {
        var averages: [ObservationMetric: Double] = [:]
        var spreads: [ObservationMetric: MetricSpread] = [:]

        func average(_ metric: ObservationMetric) -> Double? { averages[metric] }
    }

    /// ブリストル値・腹痛・急な便意は、日ごとの平均ではなく記録 1 件ずつの平均を取る。
    /// 排便回数が多い日と少ない日を同じ重みで扱わないため。
    /// 排便回数だけは 1 日 1 件なので、記録が付いた日を分母にする。
    private static func metricValues(recordedTallies: [DailyTally], movements: [BowelMovement]) -> MetricValues {
        var values = MetricValues()

        func put(_ metric: ObservationMetric, _ samples: [Double]) {
            guard let mean = average(samples), let minimum = samples.min(), let maximum = samples.max() else { return }
            values.averages[metric] = mean
            values.spreads[metric] = MetricSpread(minimum: minimum, maximum: maximum)
        }

        put(.bowelCount, recordedTallies.map { Double($0.bowelCount) })
        put(.bristol, movements.map { Double($0.bristolScale.rawValue) })
        put(.abdominalPain, movements.map { Double($0.abdominalPain.rawValue) })
        put(.urgency, movements.map { Double($0.urgency.rawValue) })
        return values
    }

    // MARK: - 実施状況

    /// 観察対象ごとに、集計の窓の中で実施した／しなかったと記録した日数を数える。
    private static func adherence(
        for phase: ObservationPhase,
        targetRecords: [TargetRecord],
        window: AnalysisWindow,
        calendar: Calendar
    ) -> [TargetAdherence] {
        phase.targets.map { target in
            let marked = markedDays(for: target, in: targetRecords, window: window, calendar: calendar)
            return TargetAdherence(
                targetID: target.persistentModelID,
                name: target.name,
                completedDays: marked.completed.count,
                skippedDays: marked.skipped.count,
                analyzedDays: window.analyzedDays
            )
        }
    }

    /// 実施した日と実施しなかった日を、日付の集合として取り出す。
    /// 同じ日に複数行が残っていても 1 日として数える。
    private static func markedDays(
        for target: ObservationTarget,
        in targetRecords: [TargetRecord],
        window: AnalysisWindow,
        calendar: Calendar
    ) -> (completed: Set<Date>, skipped: Set<Date>) {
        let targetID = target.persistentModelID
        var completed: Set<Date> = []
        var skipped: Set<Date> = []

        for record in targetRecords where record.target?.persistentModelID == targetID {
            let day = calendar.startOfDay(for: record.date)
            guard window.contains(day, calendar: calendar) else { continue }
            if record.isCompleted {
                completed.insert(day)
            } else {
                skipped.insert(day)
            }
        }

        // 同じ日に両方残っていたら実施の側を採る。二重に数えて日数が水増しされるのを避ける。
        skipped.subtract(completed)
        return (completed, skipped)
    }

    // MARK: -

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
