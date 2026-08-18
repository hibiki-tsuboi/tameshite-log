#if DEBUG
import Foundation
import SwiftData

/// プレビューと動作確認のための架空データ（30 日分）。
///
/// 数値は UI の見え方を確かめるために作ったもので、薬の効果を表すものではない。
/// 実行ごとに変わると差分が読めないので、日付インデックスから決まる疑似乱数で生成する。
enum SampleData {

    /// 1 日の記録をどのくらいの範囲で作るかの指定。
    private struct DayProfile {
        var count: ClosedRange<Int>
        var bristol: ClosedRange<Int>
        var pain: ClosedRange<Int>
        var urgency: ClosedRange<Int>
    }

    private struct PhaseSpec {
        var name: String
        var type: PhaseType
        var days: Int
        var targetNames: [String]
        var start: DayProfile
        /// 日数の経過とともに変化する場合の終了時プロファイル。nil なら変化しない。
        var end: DayProfile?
    }

    private static let specs: [PhaseSpec] = [
        PhaseSpec(
            name: "いつもの状態", type: .baseline, days: 6, targetNames: [],
            start: DayProfile(count: 4...6, bristol: 5...7, pain: 1...2, urgency: 1...2), end: nil
        ),
        PhaseSpec(
            name: "コレバイン単独", type: .intervention, days: 7, targetNames: ["コレバイン"],
            start: DayProfile(count: 1...3, bristol: 3...5, pain: 0...1, urgency: 0...1), end: nil
        ),
        PhaseSpec(
            name: "休薬", type: .washout, days: 4, targetNames: [],
            start: DayProfile(count: 4...5, bristol: 5...7, pain: 1...2, urgency: 1...2), end: nil
        ),
        PhaseSpec(
            name: "イリボー単独", type: .intervention, days: 8, targetNames: ["イリボー"],
            start: DayProfile(count: 4...4, bristol: 5...6, pain: 1...2, urgency: 1...2),
            end: DayProfile(count: 2...3, bristol: 4...5, pain: 0...1, urgency: 0...1)
        ),
        PhaseSpec(
            name: "イリボー + コレバイン", type: .intervention, days: 5, targetNames: ["イリボー", "コレバイン"],
            start: DayProfile(count: 1...2, bristol: 3...4, pain: 0...1, urgency: 0...0), end: nil
        ),
    ]

    private static var totalDays: Int { specs.reduce(0) { $0 + $1.days } }

    @MainActor
    static func populate(_ context: ModelContext, today: Date = .now, calendar: Calendar = .current) {
        let store = ObservationStore(context: context, calendar: calendar)
        store.deleteEverything()

        let targets = ["コレバイン", "イリボー"].reduce(into: [String: ObservationTarget]()) { result, name in
            result[name] = store.createTarget(name: name, type: .medication, note: "")
        }

        let todayStart = calendar.startOfDay(for: today)
        let firstDay = calendar.date(byAdding: .day, value: -(totalDays - 1), to: todayStart) ?? todayStart

        let plan = store.createPlan(name: "下痢の経過観察", startDate: firstDay)

        var dayIndex = 0
        for (specIndex, spec) in specs.enumerated() {
            let start = calendar.date(byAdding: .day, value: dayIndex, to: firstDay) ?? firstDay
            // 最後のフェーズは「継続中」にして、今日画面に現在のフェーズが出る状態にする。
            let isLast = specIndex == specs.count - 1
            let end = calendar.date(byAdding: .day, value: dayIndex + spec.days - 1, to: firstDay)

            let phase = ObservationPhase(
                name: spec.name,
                type: spec.type,
                startDate: start,
                endDate: isLast ? nil : end,
                targets: spec.targetNames.compactMap { targets[$0] }
            )
            phase.plan = plan
            context.insert(phase)
            plan.phases.append(phase)

            for offset in 0..<spec.days {
                let day = calendar.date(byAdding: .day, value: dayIndex + offset, to: firstDay) ?? firstDay
                guard day <= todayStart else { break }
                let progress = spec.days > 1 ? Double(offset) / Double(spec.days - 1) : 0
                let profile = interpolate(from: spec.start, to: spec.end, progress: progress)
                generateDay(day, profile: profile, spec: spec, targets: targets, context: context, calendar: calendar)
            }
            dayIndex += spec.days
        }

        try? context.save()
    }

    @MainActor
    private static func generateDay(
        _ day: Date,
        profile: DayProfile,
        spec: PhaseSpec,
        targets: [String: ObservationTarget],
        context: ModelContext,
        calendar: Calendar
    ) {
        var generator = SeededGenerator(seed: UInt64(abs(day.timeIntervalSince1970.rounded()) / 86_400))

        let count = Int.random(in: profile.count, using: &generator)
        for index in 0..<count {
            // 朝から夕方にかけて散らす。
            let hour = 6 + (index * 12) / max(count, 1) + Int.random(in: 0...2, using: &generator)
            let minute = Int.random(in: 0...59, using: &generator)
            let time = calendar.date(bySettingHour: min(hour, 22), minute: minute, second: 0, of: day) ?? day

            let movement = BowelMovement(
                recordedAt: time,
                bristolScale: BristolScale(rawValue: Int.random(in: profile.bristol, using: &generator)) ?? .normal,
                abdominalPain: SymptomLevel(rawValue: Int.random(in: profile.pain, using: &generator)) ?? .absent,
                urgency: SymptomLevel(rawValue: Int.random(in: profile.urgency, using: &generator)) ?? .absent,
                calendar: calendar
            )
            context.insert(movement)
        }

        // まとめは毎日は書かれない想定にして、実際の使われ方に近づける。
        if Int.random(in: 0...3, using: &generator) > 0 {
            let condition: ConditionLevel = count >= 4 ? .poor : (count >= 3 ? .fair : .good)
            let record = DailyRecord(
                date: day,
                overallCondition: condition,
                abdominalCondition: profile.pain.upperBound >= 2 ? .fair : .good,
                calendar: calendar
            )
            context.insert(record)
        }

        for name in spec.targetNames {
            guard let target = targets[name] else { continue }
            let hour = name == "イリボー" ? 8 : 20
            let record = TargetRecord(date: day, target: target, calendar: calendar)
            record.markCompleted(at: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day)
            context.insert(record)
        }
    }

    private static func interpolate(from start: DayProfile, to end: DayProfile?, progress: Double) -> DayProfile {
        guard let end else { return start }
        func blend(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> ClosedRange<Int> {
            let lower = Int((Double(a.lowerBound) + (Double(b.lowerBound) - Double(a.lowerBound)) * progress).rounded())
            let upper = Int((Double(a.upperBound) + (Double(b.upperBound) - Double(a.upperBound)) * progress).rounded())
            return min(lower, upper)...max(lower, upper)
        }
        return DayProfile(
            count: blend(start.count, end.count),
            bristol: blend(start.bristol, end.bristol),
            pain: blend(start.pain, end.pain),
            urgency: blend(start.urgency, end.urgency)
        )
    }
}

/// 生成結果を毎回同じにするための決定的な乱数生成器。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SampleData {
    /// プレビュー用のメモリ内コンテナ。
    @MainActor
    static let previewContainer: ModelContainer = {
        let container = try! ModelContainer(
            for: ObservationPlan.self, ObservationPhase.self, ObservationTarget.self,
            DailyRecord.self, TargetRecord.self, BowelMovement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        populate(container.mainContext)
        return container
    }()

    /// プレビューで「有効なプラン」を必要とするビュー向け。
    @MainActor
    static var previewPlan: ObservationPlan {
        ObservationStore(context: previewContainer.mainContext).activePlan()
            ?? ObservationPlan(name: "下痢の経過観察")
    }

    /// 記録が 1 件もない状態のプレビュー用コンテナ。
    @MainActor
    static let emptyPreviewContainer: ModelContainer = {
        try! ModelContainer(
            for: ObservationPlan.self, ObservationPhase.self, ObservationTarget.self,
            DailyRecord.self, TargetRecord.self, BowelMovement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }()
}
#endif
