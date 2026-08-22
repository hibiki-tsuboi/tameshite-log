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

    /// 集計から外す、フェーズ開始直後の日数。
    ///
    /// 薬もサプリも運動も初日から効くとは限らないので、立ち上がりの数日を平均に入れると
    /// フェーズ全体が薄まる。外した日の記録は消さず、グラフにもそのまま点を打つ。
    /// 平均と比較の分母からだけ抜く。
    var warmupDays: Int = 0

    var plan: ObservationPlan?
    var targets: [ObservationTarget] = []

    init(
        name: String,
        type: PhaseType = .intervention,
        startDate: Date,
        endDate: Date? = nil,
        note: String = "",
        warmupDays: Int = 0,
        targets: [ObservationTarget] = []
    ) {
        self.name = name
        self.type = type
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.note = note
        self.warmupDays = max(0, warmupDays)
        self.targets = targets
    }

    var isOngoing: Bool { endDate == nil }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard day >= calendar.startOfDay(for: startDate) else { return false }
        guard let endDate else { return true }
        return day <= calendar.startOfDay(for: endDate)
    }

    /// 集計を始める日。`warmupDays` のぶん開始日から後ろにずらす。
    /// 記録の絞り込みはここから `effectiveEndDate(asOf:)` までで行う。
    func analysisStartDate(calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: startDate)
        guard warmupDays > 0 else { return start }
        return calendar.date(byAdding: .day, value: warmupDays, to: start) ?? start
    }

    /// 集計に使う終了日。継続中なら「今日」で打ち切る。
    func effectiveEndDate(asOf today: Date = .now, calendar: Calendar = .current) -> Date {
        let cappedToday = calendar.startOfDay(for: today)
        guard let endDate else { return max(cappedToday, calendar.startOfDay(for: startDate)) }
        return min(calendar.startOfDay(for: endDate), max(cappedToday, calendar.startOfDay(for: startDate)))
    }

    /// 観察対象を、並び順の決まった形で取り出す。
    ///
    /// `targets` は多対多で、SwiftData は並び順を保証しない。実際に起動ごとに入れ替わり、
    /// チェックリストの行順・`targetSummary`・経過画面の実施記録の行順が揺れる。同じ日の
    /// 同じ画面が開くたびに違う順で出ると、目で追っている側は探し直すことになる。
    /// `ObservationPlan.orderedPhases` と同じように、読むときに並べ直す。
    ///
    /// 作成時刻が同じになったときは名前で決める。ここで決め切らないと、揺れる余地が残る。
    var orderedTargets: [ObservationTarget] {
        targets.sorted {
            $0.createdAt == $1.createdAt ? $0.name < $1.name : $0.createdAt < $1.createdAt
        }
    }

    var targetSummary: String {
        targets.isEmpty ? "観察対象なし" : orderedTargets.map(\.name).joined(separator: " + ")
    }
}
