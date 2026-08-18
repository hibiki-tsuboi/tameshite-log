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

    /// 新しいフェーズを開始する。継続中のフェーズは前日で閉じ、継続中が 2 つ並ばないようにする。
    ///
    /// 閉じる対象を「開始日が新しい開始日より前のもの」に絞ると、継続中フェーズの開始日と同じ日か
    /// それより前の日で新しいフェーズを始めたときに閉じ漏れが出て、継続中が 2 つ残る。
    /// `ObservationPlan.phase(on:)` は開始日が後のものを採るので、そうなると片方の期間が
    /// 黙って隠れてしまう。開始日の前後によらず、継続中はすべて閉じる。
    ///
    /// 終了日は自分の開始日より前にはしない。1 日も存在しないフェーズを作らないためで、
    /// この下限に当たるのは開始日が新しい開始日以降だった場合だけ。
    /// その組み合わせは `PhaseStartSheet` が開始日の下限で防いでいる。
    @discardableResult
    func startPhase(
        name: String,
        type: PhaseType,
        targets: [ObservationTarget] = [],
        on date: Date = .now,
        in plan: ObservationPlan,
        note: String = "",
        warmupDays: Int = 0
    ) -> ObservationPhase {
        let start = calendar.startOfDay(for: date)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: start) ?? start

        for phase in plan.orderedPhases where phase.isOngoing {
            phase.endDate = max(previousDay, calendar.startOfDay(for: phase.startDate))
        }

        let phase = ObservationPhase(
            name: name,
            type: type,
            startDate: start,
            note: note,
            warmupDays: warmupDays,
            targets: targets
        )
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
        // 「排便なし」と記録した日に排便を足したら、その印は下ろす。
        // 残しておくと同じ日について矛盾した記録が併存する。
        if let record = dailyRecord(for: movement.date), record.hadNoBowelMovement {
            record.hadNoBowelMovement = false
            pruneIfEmpty(record)
        }
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

    /// その日を「排便なし」として記録する／取り消す。
    ///
    /// 排便記録が 0 件でも「なかった」と「まだ書いていない」は別物なので、
    /// 前者は明示的に残す。取り消して他に何も書かれていなければ行ごと片付ける。
    func setNoBowelMovement(_ isNone: Bool, for date: Date) {
        if isNone {
            let record = ensureDailyRecord(for: date)
            record.hadNoBowelMovement = true
            record.updatedAt = .now
        } else if let record = dailyRecord(for: date) {
            record.hadNoBowelMovement = false
            pruneIfEmpty(record)
        }
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

    /// 未記録 → 実施した → 実施しなかった → 未記録 の順に切り替える。
    ///
    /// 「実施しなかった」を「未記録」と区別できないと、実施の有無で記録を見くらべられない。
    /// 一方で押し間違いを未記録へ戻せないと、誤った「実施しなかった」が集計に残り続けるので、
    /// 3 つ目で行を消して最初の状態に戻す。
    func toggleTarget(_ target: ObservationTarget, on date: Date, at time: Date = .now) {
        guard let record = targetRecord(for: target, on: date) else {
            let record = TargetRecord(date: date, target: target, calendar: calendar)
            record.markCompleted(at: completionTime(on: date, preferring: time))
            context.insert(record)
            return
        }

        if record.isCompleted {
            record.markNotCompleted()
        } else {
            context.delete(record)
        }
    }

    /// 実施時刻を付け替える。時と分だけを受け取り、日付はその記録の日に合わせる。
    ///
    /// ピッカーは時と分しか編集しないので、保存済みの値の日付が別の日だと、
    /// 何度編集してもその日から動かない。ここで日付ごと組み直して直す。
    func updateCompletionTime(_ record: TargetRecord, to time: Date) {
        let day = calendar.startOfDay(for: record.date)
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        record.completedAt = calendar.date(
            bySettingHour: parts.hour ?? 12,
            minute: parts.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    /// 実施時刻をその日の中に収める。
    ///
    /// 既定は `.now` なので、カレンダーから過去の日を開いて実施済みにすると
    /// 「今日の時刻」が入ってしまう。実施時刻のピッカーは時と分しか編集しないため、
    /// 一度ずれた日付はあとから直せない。
    /// 渡された時刻がその日のものでなければ、正午に置く（記録の後追い入力と同じ扱い）。
    private func completionTime(on date: Date, preferring time: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        guard !calendar.isDate(time, inSameDayAs: day) else { return time }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    // MARK: - データ管理

    func deleteAllRecords() {
        deleteAll(BowelMovement.self)
        deleteAll(DailyRecord.self)
        deleteAll(TargetRecord.self)
        save()
    }

    func deleteEverything() {
        deleteAllRecords()
        deleteAll(ObservationPhase.self)
        deleteAll(ObservationPlan.self)
        deleteAll(ObservationTarget.self)
        save()
    }

    /// 1 件ずつ取り出して消す。
    ///
    /// `context.delete(model:)` の一括削除はリレーションの規則を通らず、
    /// TargetRecord のように逆参照を持つモデルが消え残る。しかも `try?` で
    /// 握りつぶすと、削除したつもりのデータが残ったままになる。
    private func deleteAll<Model: PersistentModel>(_ type: Model.Type) {
        let items = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        for item in items {
            context.delete(item)
        }
    }

    /// 削除は取り消せない操作なので、自動保存を待たずにここで確定させる。
    private func save() {
        try? context.save()
    }
}
