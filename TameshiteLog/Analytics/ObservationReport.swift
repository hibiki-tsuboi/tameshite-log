import Foundation
import SwiftData

/// 書き出し 1 回分の中身。紙面と CSV で同じ数値を使うためのひとまとめ。
///
/// 集計そのものは `ObservationAnalyzer` に任せ、ここでは
/// 「どの期間の、どの行を並べるか」だけを決める。
///
/// フェーズ別の集計は期間で切り取らず、フェーズ全体の記録から計算する。
/// 期間を絞ったときだけ経過画面と違う平均が出ると、どちらが本当なのか分からなくなるため。
struct ObservationReport: Sendable {

    /// 日別表の 1 行。グラフと同じ `DailyTally` に、紙面で見せたい情報を足しただけ。
    struct DayRow: Identifiable, Sendable {
        var tally: DailyTally
        var phaseName: String
        var completedTargets: [String]
        var note: String

        var id: Date { tally.date }
        var date: Date { tally.date }
        var hasRecord: Bool { tally.hasRecord }
    }

    /// 排便 1 件分。明細 CSV に使う。
    struct MovementRow: Identifiable, Sendable {
        var id: PersistentIdentifier
        var recordedAt: Date
        var bristolScale: BristolScale
        var abdominalPain: SymptomLevel
        var urgency: SymptomLevel
        var phaseName: String
        var note: String
    }

    /// 紙面のメモ欄に出す 1 件。1 日のまとめと 1 回ごとのメモを同じ形で扱う。
    struct NoteEntry: Identifiable, Sendable {
        var id = UUID()
        var date: Date
        /// 排便 1 件ごとのメモなら記録時刻。1 日のまとめなら nil。
        var time: Date?
        var text: String
    }

    var planName: String
    var range: ClosedRange<Date>
    var generatedAt: Date
    /// 期間に重なるフェーズの集計。平均はフェーズ全体から計算している。
    var summaries: [PhaseSummary]
    var comparisons: [PhaseComparison]
    var days: [DayRow]
    var movements: [MovementRow]
    var notes: [NoteEntry]
    /// フェーズの色は並び順で決まる。期間で絞ってもグラフの色が画面と食い違わないよう、
    /// プラン全体での位置を持ち回る。
    var phaseColorIndices: [PersistentIdentifier: Int]

    var tallies: [DailyTally] { days.map(\.tally) }
    var elapsedDays: Int { days.count }
    var recordedDays: Int { days.filter(\.hasRecord).count }
    var totalBowelCount: Int { movements.count }
    var hasRecords: Bool { recordedDays > 0 }

    /// 値の入っている指標だけをグラフにする。空のグラフを紙面に残さないため。
    var chartableMetrics: [ObservationMetric] {
        ObservationMetric.allCases.filter { metric in
            days.contains { metric.value(in: $0.tally) != nil }
        }
    }
}

extension ObservationReport {

    static func make(
        plan: ObservationPlan,
        movements: [BowelMovement],
        dailyRecords: [DailyRecord],
        targetRecords: [TargetRecord],
        range: ClosedRange<Date>,
        generatedAt: Date = .now,
        calendar: Calendar = .current
    ) -> ObservationReport {
        let start = calendar.startOfDay(for: range.lowerBound)
        let end = max(start, calendar.startOfDay(for: range.upperBound))

        // フェーズの平均は全期間から出す。書き出す範囲で切ると経過画面と数字が食い違う。
        let allSummaries = ObservationAnalyzer.summaries(
            for: plan,
            movements: movements,
            dailyRecords: dailyRecords,
            today: generatedAt,
            calendar: calendar
        )
        let colorIndices = allSummaries.enumerated().reduce(into: [PersistentIdentifier: Int]()) { result, item in
            result[item.element.id] = item.offset
        }
        let visible = allSummaries.filter { $0.startDate <= end && $0.effectiveEndDate >= start }
        let visibleIDs = Set(visible.map(\.id))
        let comparisons = ObservationAnalyzer.comparisons(for: allSummaries)
            .filter { visibleIDs.contains($0.subject.id) }

        let periodMovements = movements
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.recordedAt < $1.recordedAt }
        let periodDailyRecords = dailyRecords.filter { $0.date >= start && $0.date <= end }

        let tallies = ObservationAnalyzer.dailyTallies(
            movements: periodMovements,
            dailyRecords: periodDailyRecords,
            in: start...end,
            calendar: calendar
        )

        let completedByDay = Dictionary(
            grouping: targetRecords.filter { $0.isCompleted && $0.date >= start && $0.date <= end },
            by: { calendar.startOfDay(for: $0.date) }
        )
        let noteByDay = Dictionary(
            periodDailyRecords.map { (calendar.startOfDay(for: $0.date), $0.note) },
            uniquingKeysWith: { first, _ in first }
        )

        let days = tallies.map { tally in
            DayRow(
                tally: tally,
                phaseName: plan.phase(on: tally.date, calendar: calendar)?.name ?? "",
                completedTargets: Set((completedByDay[tally.date] ?? []).compactMap { $0.target?.name })
                    .sorted(),
                note: noteByDay[tally.date] ?? ""
            )
        }

        let movementRows = periodMovements.map { movement in
            MovementRow(
                id: movement.persistentModelID,
                recordedAt: movement.recordedAt,
                bristolScale: movement.bristolScale,
                abdominalPain: movement.abdominalPain,
                urgency: movement.urgency,
                phaseName: plan.phase(on: movement.date, calendar: calendar)?.name ?? "",
                note: movement.note
            )
        }

        // まとめのメモと 1 回ごとのメモを、日付と時刻の順に混ぜて 1 本の並びにする。
        let summaryNotes = periodDailyRecords.compactMap { record -> NoteEntry? in
            let text = record.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return NoteEntry(date: calendar.startOfDay(for: record.date), time: nil, text: text)
        }
        let movementNotes = periodMovements.compactMap { movement -> NoteEntry? in
            let text = movement.note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return NoteEntry(
                date: calendar.startOfDay(for: movement.date),
                time: movement.recordedAt,
                text: text
            )
        }
        let notes = (summaryNotes + movementNotes).sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            // まとめは時刻を持たないので、その日の先頭に置く。
            return ($0.time ?? .distantPast) < ($1.time ?? .distantPast)
        }

        return ObservationReport(
            planName: plan.name,
            range: start...end,
            generatedAt: generatedAt,
            summaries: visible,
            comparisons: comparisons,
            days: days,
            movements: movementRows,
            notes: notes,
            phaseColorIndices: colorIndices
        )
    }
}
