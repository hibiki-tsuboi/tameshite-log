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

    // 同じプランの中では、1 日が属するフェーズは高々 1 つ。フェーズ同士は重ならない。
    //
    // 記録はフェーズに紐づかず日付から導出するので、重なったとたんに「この日はどちらの
    // フェーズか」が決まらなくなる。`ObservationPlan.phase(on:)` は開始日が後のほうを返し、
    // 一方で `ObservationAnalyzer` は同じ記録を両方のフェーズの平均に入れるため、
    // 画面に出ているフェーズと数字の中身が食い違ったまま気づけない。
    // 開始日と終了日を動かす操作はこの節をすべて通し、隣と重ならないところまで詰める。
    //
    // 隙間は許す。どのフェーズにも属さない日はあり得るし、あとから拾えるようにしてある。

    /// 開始日の順に見たときの、`phase` のひとつ前。
    func previousPhase(of phase: ObservationPhase) -> ObservationPhase? {
        guard let index = orderedIndex(of: phase), index > 0 else { return nil }
        return phase.plan?.orderedPhases[index - 1]
    }

    /// 開始日の順に見たときの、`phase` のひとつ後。
    func nextPhase(of phase: ObservationPhase) -> ObservationPhase? {
        guard let phases = phase.plan?.orderedPhases,
              let index = orderedIndex(of: phase),
              index + 1 < phases.count else { return nil }
        return phases[index + 1]
    }

    /// 継続中に戻せるのは最後のフェーズだけ。
    /// 終了日を外すと以降ずっと続くことになるので、後ろにフェーズがあると全部を飲み込む。
    func canBeOngoing(_ phase: ObservationPhase) -> Bool {
        nextPhase(of: phase) == nil
    }

    /// 新しいフェーズの開始日として選べる範囲。
    ///
    /// 下限は既存フェーズの開始日のうち最も遅い日の翌日。継続中かどうかで分けないのは、
    /// 閉じたフェーズの内側から始めても期間が重なるため。こう決めておくと、新しい開始日の
    /// 前日で既存のフェーズを閉じたときに 1 日も残らないフェーズができない。
    /// フェーズがまだ 1 つもなければ下限なし。
    ///
    /// 上限は今日。未来から始まるフェーズはその日まで記録もできず、今日がどのフェーズにも
    /// 属さない状態になるだけで、`effectiveEndDate(asOf:)` も今日で頭打ちになる。
    func newPhaseStartRange(in plan: ObservationPlan, asOf today: Date = .now) -> ClosedRange<Date> {
        let latest = plan.phases.map { calendar.startOfDay(for: $0.startDate) }.max()
        let lower = latest.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? .distantPast
        return Self.range(from: lower, to: calendar.startOfDay(for: today))
    }

    /// 既存フェーズの開始日として選べる範囲。
    ///
    /// 下限は前のフェーズの「終了日」ではなく「開始日の翌日」。終了日で挟むと、隣り合った
    /// フェーズの境目を前に動かしたいときに、先に前のフェーズを縮めて隙間を空けないと
    /// 目的の日が選べない。開始日を基準にしておけば 1 回の操作で済み、はみ出したぶんは
    /// `moveStart(of:to:)` が前のフェーズの終了日を詰めて追従させる。
    func startDateRange(for phase: ObservationPhase, asOf today: Date = .now) -> ClosedRange<Date> {
        let lower = previousPhase(of: phase)
            .map { calendar.startOfDay(for: $0.startDate) }
            .flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } ?? .distantPast
        let ownEnd = phase.endDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
        return Self.range(from: lower, to: min(ownEnd, calendar.startOfDay(for: today)))
    }

    /// 既存フェーズの終了日として選べる範囲。
    ///
    /// 上限は次のフェーズの前日。境目は後ろのフェーズの開始日で動かす決まりなので、
    /// 終了日を動かせるのは隙間を空ける方向（と、空いている隙間の中）だけ。
    func endDateRange(for phase: ObservationPhase, asOf today: Date = .now) -> ClosedRange<Date> {
        let upper = nextPhase(of: phase)
            .map { calendar.startOfDay(for: $0.startDate) }
            .flatMap { calendar.date(byAdding: .day, value: -1, to: $0) } ?? .distantFuture
        return Self.range(
            from: calendar.startOfDay(for: phase.startDate),
            to: min(upper, calendar.startOfDay(for: today))
        )
    }

    /// 新しいフェーズを開始する。開始日より前に始まっているフェーズは前日で閉じる。
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
        closePhases(startingBefore: start, in: plan)

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

    /// 開始日を動かす。前のフェーズが新しい開始日に食い込んでいたら、その前日まで詰める。
    func moveStart(of phase: ObservationPhase, to date: Date) {
        let start = calendar.startOfDay(for: date)
        guard start != calendar.startOfDay(for: phase.startDate) else { return }

        phase.startDate = start
        // 開始日が自分の終了日を追い越さないようにする。ピッカーの上限が防いでいるので、
        // ここに掛かるのは範囲を通らずに呼ばれたときだけ。
        if let end = phase.endDate, calendar.startOfDay(for: end) < start {
            phase.endDate = start
        }
        if let plan = phase.plan {
            closePhases(startingBefore: start, in: plan, excluding: phase)
        }
    }

    /// 終了日を決める。`nil` で継続中に戻す（最後のフェーズのときだけ）。
    /// 次のフェーズに食い込む日を渡されても、その前日で止める。
    func setEnd(of phase: ObservationPhase, to date: Date?) {
        guard let date else {
            if canBeOngoing(phase) { phase.endDate = nil }
            return
        }
        let range = endDateRange(for: phase)
        phase.endDate = min(max(calendar.startOfDay(for: date), range.lowerBound), range.upperBound)
    }

    /// 継続中のフェーズを指定日で終える。
    func endPhase(_ phase: ObservationPhase, on date: Date = .now) {
        setEnd(of: phase, to: date)
    }

    func delete(_ phase: ObservationPhase) {
        context.delete(phase)
    }

    /// `date` から始まるフェーズと重ならないよう、それより前に始まっているフェーズを前日で閉じる。
    ///
    /// 継続中かどうかは見ない。継続中だけを閉じると、閉じたフェーズの内側から新しいフェーズを
    /// 始めたときに重なりが残る。逆に終了日が `date` より前で収まっているフェーズは触らない。
    /// 隙間を勝手に埋めてしまわないため。
    ///
    /// 終了日は自分の開始日より前にはしない。1 日も存在しないフェーズを作らないためで、
    /// この下限に当たるのは開始日が `date` 以降だった場合だけ。そのフェーズは詰めようがなく、
    /// 呼び出し側が `newPhaseStartRange(in:)` や `startDateRange(for:)` の下限で防いでいる。
    private func closePhases(
        startingBefore date: Date,
        in plan: ObservationPlan,
        excluding excluded: ObservationPhase? = nil
    ) {
        let previousDay = calendar.date(byAdding: .day, value: -1, to: date) ?? date

        for phase in plan.phases where phase.persistentModelID != excluded?.persistentModelID {
            let start = calendar.startOfDay(for: phase.startDate)
            guard start < date else { continue }
            if let end = phase.endDate, calendar.startOfDay(for: end) < date { continue }
            phase.endDate = max(previousDay, start)
        }
    }

    private func orderedIndex(of phase: ObservationPhase) -> Int? {
        phase.plan?.orderedPhases.firstIndex { $0.persistentModelID == phase.persistentModelID }
    }

    /// 下限が上限を上回らないようにした範囲。`ClosedRange` は逆転すると落ちるので、
    /// ピッカーに渡す範囲は必ずここを通す。
    private static func range(from lower: Date, to upper: Date) -> ClosedRange<Date> {
        lower...max(lower, upper)
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
