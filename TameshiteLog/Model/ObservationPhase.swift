import Foundation
import SwiftData

/// フェーズの種類。内部表現は baseline / intervention / washout の 3 つに固定し、
/// 画面ではもう少しやわらかい言葉で見せる。
enum PhaseType: String, CaseIterable, Codable, Identifiable, Sendable {
    case baseline
    case intervention
    case washout

    var id: String { rawValue }

    var label: String {
        switch self {
        case .baseline: "いつもの状態"
        case .intervention: "試している期間"
        case .washout: "お休み期間"
        }
    }

    var detail: String {
        switch self {
        case .baseline: "何かを始める前の、普段の状態を記録する期間です。"
        case .intervention: "何かを試している期間です。"
        case .washout: "試していたことを一度やめている期間です。"
        }
    }

    var symbolName: String {
        switch self {
        case .baseline: "circle.dashed"
        case .intervention: "flask.fill"
        case .washout: "pause.circle.fill"
        }
    }
}

/// 観察プランを区切る一区間。「この期間はこうしていた」という単位。
@Model
final class ObservationPhase {
    var name: String = ""
    var type: PhaseType = PhaseType.intervention
    var startDate: Date = Date.distantPast
    /// nil は「継続中」を意味する。次のフェーズを始めたときに閉じる。
    var endDate: Date?
    var note: String = ""

    var plan: ObservationPlan?
    var targets: [ObservationTarget] = []

    init(
        name: String,
        type: PhaseType = .intervention,
        startDate: Date,
        endDate: Date? = nil,
        note: String = "",
        targets: [ObservationTarget] = []
    ) {
        self.name = name
        self.type = type
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.note = note
        self.targets = targets
    }

    var isOngoing: Bool { endDate == nil }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard day >= calendar.startOfDay(for: startDate) else { return false }
        guard let endDate else { return true }
        return day <= calendar.startOfDay(for: endDate)
    }

    /// 集計に使う終了日。継続中なら「今日」で打ち切る。
    func effectiveEndDate(asOf today: Date = .now, calendar: Calendar = .current) -> Date {
        let cappedToday = calendar.startOfDay(for: today)
        guard let endDate else { return max(cappedToday, calendar.startOfDay(for: startDate)) }
        return min(calendar.startOfDay(for: endDate), max(cappedToday, calendar.startOfDay(for: startDate)))
    }

    var targetSummary: String {
        targets.isEmpty ? "観察対象なし" : targets.map(\.name).joined(separator: " + ")
    }
}
