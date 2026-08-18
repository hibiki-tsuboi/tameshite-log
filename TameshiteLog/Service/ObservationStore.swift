import Foundation
import SwiftData

/// SwiftData への書き込みをまとめる薄い層。
///
/// ビューから `ModelContext` を直接触ると「フェーズを開始したら前のフェーズを閉じる」ような
/// 複数モデルにまたがる規則が散らばるので、そうした操作はここに集める。
struct ObservationStore {
    let context: ModelContext
    var calendar: Calendar = .current

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: - プラン

    func allPlans() -> [ObservationPlan] {
        let descriptor = FetchDescriptor<ObservationPlan>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func activePlan() -> ObservationPlan? {
        let descriptor = FetchDescriptor<ObservationPlan>(predicate: #Predicate { $0.isActive })
        return (try? context.fetch(descriptor))?.first
    }

    /// 有効なプランは常に 1 つ。切り替えるときに他を落とす。
    func activate(_ plan: ObservationPlan) {
        for other in allPlans() where other.persistentModelID != plan.persistentModelID {
            other.isActive = false
        }
        plan.isActive = true
    }

    @discardableResult
    func createPlan(name: String, startDate: Date = .now, activate shouldActivate: Bool = true) -> ObservationPlan {
        let plan = ObservationPlan(name: name, startDate: startDate)
        context.insert(plan)
        if shouldActivate { activate(plan) }
        return plan
    }

    func delete(_ plan: ObservationPlan) {
        let wasActive = plan.isActive
        context.delete(plan)
        if wasActive, let next = allPlans().first(where: { $0.persistentModelID != plan.persistentModelID }) {
            activate(next)
        }
    }

    // MARK: - フェーズ

    /// 新しいフェーズを開始する。継続中のフェーズがあれば前日で閉じ、期間が重ならないようにする。
    @discardableResult
    func startPhase(
        name: String,
        type: PhaseType,
        targets: [ObservationTarget] = [],
        on date: Date = .now,
        in plan: ObservationPlan,
        note: String = ""
    ) -> ObservationPhase {
        let start = calendar.startOfDay(for: date)

        for phase in plan.orderedPhases where phase.isOngoing && phase.startDate < start {
            phase.endDate = calendar.date(byAdding: .day, value: -1, to: start)
        }

        let phase = ObservationPhase(name: name, type: type, startDate: start, note: note, targets: targets)
        phase.plan = plan
        context.insert(phase)
        plan.phases.append(phase)
        return phase
    }

    /// 継続中のフェーズを指定日で終える。
    func endPhase(_ phase: ObservationPhase, on date: Date = .now) {
        phase.endDate = calendar.startOfDay(for: date)
    }

    func delete(_ phase: ObservationPhase) {
        context.delete(phase)
    }

    // MARK: - 観察対象

    func allTargets() -> [ObservationTarget] {
        let descriptor = FetchDescriptor<ObservationTarget>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func createTarget(name: String, type: TargetType, note: String = "") -> ObservationTarget {
        let target = ObservationTarget(name: name, type: type, note: note)
        context.insert(target)
        return target
    }

    func delete(_ target: ObservationTarget) {
        context.delete(target)
    }

    // MARK: - 排便記録

    func movements(on date: Date) -> [BowelMovement] {
        let day = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        let descriptor = FetchDescriptor<BowelMovement>(
            predicate: #Predicate { $0.date >= day && $0.date < next },
            sortBy: [SortDescriptor(\.recordedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    func addMovement(
        at time: Date = .now,
        bristolScale: BristolScale,
        abdominalPain: SymptomLevel = .absent,
        urgency: SymptomLevel = .absent,
        note: String = ""
    ) -> BowelMovement {
        let movement = BowelMovement(
            recordedAt: time,
            bristolScale: bristolScale,
            abdominalPain: abdominalPain,
            urgency: urgency,
            note: note,
            calendar: calendar
        )
        context.insert(movement)
        return movement
    }

    func delete(_ movement: BowelMovement) {
        context.delete(movement)
    }

    // MARK: - 1 日のまとめ

    func dailyRecord(for date: Date) -> DailyRecord? {
        let day = calendar.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyRecord>(predicate: #Predicate { $0.date == day })
        return (try? context.fetch(descriptor))?.first
    }

    /// まとめは任意入力なので、書き込みが始まって初めて作る。
    func ensureDailyRecord(for date: Date) -> DailyRecord {
        if let existing = dailyRecord(for: date) { return existing }
        let record = DailyRecord(date: date, calendar: calendar)
        context.insert(record)
        return record
    }

    /// 入力を全部消したまとめは残さない。カレンダーに空の記録印が出てしまうため。
    func pruneIfEmpty(_ record: DailyRecord) {
        if record.isEmpty {
            context.delete(record)
        } else {
            record.updatedAt = .now
        }
    }

    // MARK: - 観察対象の実施記録

    func targetRecords(on date: Date) -> [TargetRecord] {
        let day = calendar.startOfDay(for: date)
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        let descriptor = FetchDescriptor<TargetRecord>(predicate: #Predicate { $0.date >= day && $0.date < next })
        return (try? context.fetch(descriptor)) ?? []
    }

    func targetRecord(for target: ObservationTarget, on date: Date) -> TargetRecord? {
        let targetID = target.persistentModelID
        return targetRecords(on: date).first { $0.target?.persistentModelID == targetID }
    }

    /// 実施済み／未実施を切り替える。実施にしたときは時刻も残す。
    func toggleTarget(_ target: ObservationTarget, on date: Date, at time: Date = .now) {
        if let record = targetRecord(for: target, on: date) {
            if record.isCompleted {
                record.markNotCompleted()
            } else {
                record.markCompleted(at: time)
            }
        } else {
            let record = TargetRecord(date: date, target: target, calendar: calendar)
            record.markCompleted(at: time)
            context.insert(record)
        }
    }

    // MARK: - データ管理

    func deleteAllRecords() {
        try? context.delete(model: BowelMovement.self)
        try? context.delete(model: DailyRecord.self)
        try? context.delete(model: TargetRecord.self)
    }

    func deleteEverything() {
        deleteAllRecords()
        try? context.delete(model: ObservationPhase.self)
        try? context.delete(model: ObservationPlan.self)
        try? context.delete(model: ObservationTarget.self)
    }
}
