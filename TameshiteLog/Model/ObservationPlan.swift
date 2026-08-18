import Foundation
import SwiftData

/// 一連の観察のまとまり。複数のフェーズを時系列に並べて持つ。
@Model
final class ObservationPlan {
    var name: String = ""
    var startDate: Date = Date.distantPast
    var endDate: Date?
    var createdAt: Date = Date.distantPast
    /// 「今日」画面が対象にするプラン。同時に有効なのは 1 つだけ（ObservationStore が保証する）。
    var isActive: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ObservationPhase.plan)
    var phases: [ObservationPhase] = []

    init(name: String, startDate: Date = .now, endDate: Date? = nil, createdAt: Date = .now, isActive: Bool = false) {
        self.name = name
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate
        self.createdAt = createdAt
        self.isActive = isActive
    }

    var orderedPhases: [ObservationPhase] {
        phases.sorted { $0.startDate < $1.startDate }
    }

    /// その日のフェーズ。フェーズ同士は重ならない（`ObservationStore` が保証する）ので、
    /// 当てはまるのは高々 1 つ。`last` はその前提が崩れたときに、カレンダーの帯の色と
    /// 同じフェーズを返すための保険。
    func phase(on date: Date, calendar: Calendar = .current) -> ObservationPhase? {
        orderedPhases.last { $0.contains(date, calendar: calendar) }
    }

    /// 比較の基準にする「いつもの状態」。最初のベースラインを使う。
    var baselinePhase: ObservationPhase? {
        orderedPhases.first { $0.type == .baseline }
    }

    /// 記録が存在しうる範囲。グラフの X 軸の既定値に使う。
    func observedRange(asOf today: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date>? {
        let phases = orderedPhases
        guard let first = phases.first else { return nil }
        let start = calendar.startOfDay(for: first.startDate)
        let end = phases.map { $0.effectiveEndDate(asOf: today, calendar: calendar) }.max() ?? start
        guard start <= end else { return nil }
        return start...end
    }
}
