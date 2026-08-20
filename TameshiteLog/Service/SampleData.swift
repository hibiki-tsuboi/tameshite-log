#if DEBUG
import Foundation
import SwiftData
import UIKit

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
        /// 集計から外す開始直後の日数。
        var warmupDays: Int = 0
        var start: DayProfile
        /// 日数の経過とともに変化する場合の終了時プロファイル。nil なら変化しない。
        var end: DayProfile?
        /// 何日おきに「実施しなかった」日を作るか。nil なら毎日実施した記録にする。
        var skipEvery: Int?
        /// 実施しなかった日のプロファイル。nil なら実施した日と同じ。
        var skippedProfile: DayProfile?
    }

    /// 日数は画面の確認に必要な分だけ持たせている。
    /// 差を文章にするには両側に `AnalysisBasis.minimumComparisonDays` 日ぶん要るので、
    /// それを満たすフェーズと満たさないフェーズの両方が出るようにしてある。
    private static let specs: [PhaseSpec] = [
        PhaseSpec(
            name: "いつもの状態", type: .baseline, days: 8, targetNames: [],
            start: DayProfile(count: 4...6, bristol: 5...7, pain: 1...2, urgency: 1...2), end: nil
        ),
        // 飲み忘れのあるフェーズ。実施した日と実施しなかった日の比較を確かめるために、
        // 両側が最低日数を超えるように 1 日おきで作る。
        PhaseSpec(
            name: "コレバイン単独", type: .intervention, days: 16, targetNames: ["コレバイン"],
            start: DayProfile(count: 1...3, bristol: 3...5, pain: 0...1, urgency: 0...1), end: nil,
            skipEvery: 2,
            skippedProfile: DayProfile(count: 3...5, bristol: 5...6, pain: 1...2, urgency: 1...2)
        ),
        // 記録が最低日数に届かないフェーズ。差の数値だけが出て一文が出ない側の確認用。
        PhaseSpec(
            name: "休薬", type: .washout, days: 4, targetNames: [],
            start: DayProfile(count: 4...5, bristol: 5...7, pain: 1...2, urgency: 1...2), end: nil
        ),
        // 立ち上がりを外す設定の確認用。効き始めるまでの数日を集計から抜く。
        PhaseSpec(
            name: "イリボー単独", type: .intervention, days: 10, targetNames: ["イリボー"],
            warmupDays: 3,
            start: DayProfile(count: 4...4, bristol: 5...6, pain: 1...2, urgency: 1...2),
            end: DayProfile(count: 2...3, bristol: 4...5, pain: 0...1, urgency: 0...1)
        ),
        // 排便が 0 件の日が出るフェーズ。「排便なし」の明示を確かめるために下限を 0 にしている。
        PhaseSpec(
            name: "イリボー + コレバイン", type: .intervention, days: 5, targetNames: ["イリボー", "コレバイン"],
            start: DayProfile(count: 0...2, bristol: 3...4, pain: 0...1, urgency: 0...0), end: nil
        ),
    ]

    private static var totalDays: Int { specs.reduce(0) { $0 + $1.days } }

    /// 処方箋を撮った写真の代わりに描く紙。中身は架空で、見え方を確かめるためだけのもの。
    @MainActor
    private static func placeholderPaper() -> Data? {
        let size = CGSize(width: 840, height: 1188)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let title = "処方箋（サンプル）"
            let lines = [
                "さくら台内科クリニック",
                "",
                "Rp.",
                "1) コレバイン ミニ83%",
                "   1回 1包 1日 2回",
                "   朝食後・夕食後  14日分",
                "",
                "2) イリボー錠 5μg",
                "   1回 1錠 1日 1回  朝食後  14日分",
            ]

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 44),
                .foregroundColor: UIColor.black,
            ]
            title.draw(at: CGPoint(x: 64, y: 72), withAttributes: titleAttributes)

            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34),
                .foregroundColor: UIColor.darkGray,
            ]
            for (index, line) in lines.enumerated() {
                line.draw(at: CGPoint(x: 64, y: 180 + 52 * index), withAttributes: bodyAttributes)
            }
        }
        return image.jpegData(compressionQuality: 0.8).flatMap(AttachmentImage.prepared(from:))
    }

    @MainActor
    static func populate(_ context: ModelContext, today: Date = .now, calendar: Calendar = .current) {
        let store = ObservationStore(context: context, calendar: calendar)
        store.deleteEverything()

        let targets = ["コレバイン", "イリボー"].reduce(into: [String: ObservationTarget]()) { result, name in
            result[name] = store.createTarget(name: name, type: .medication, note: "")
        }

        // 添付のある対象を 1 つ作っておく。写真は選ばないと入らないので、
        // これがないと添付まわりの見え方をサンプルデータから確かめられない。
        if let target = targets["コレバイン"], let paper = placeholderPaper() {
            store.addAttachment(paper, to: target)
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
                warmupDays: spec.warmupDays,
                targets: spec.targetNames.compactMap { targets[$0] }
            )
            phase.plan = plan
            context.insert(phase)
            plan.phases.append(phase)

            for offset in 0..<spec.days {
                let day = calendar.date(byAdding: .day, value: dayIndex + offset, to: firstDay) ?? firstDay
                guard day <= todayStart else { break }
                let progress = spec.days > 1 ? Double(offset) / Double(spec.days - 1) : 0
                // 実施しなかった日は別のプロファイルにする。実施の有無で差が出ていないと、
                // 比較の画面ができているのか確かめられない。
                let isSkipped = spec.skipEvery.map { offset % $0 == $0 - 1 } ?? false
                let profile = isSkipped
                    ? (spec.skippedProfile ?? spec.start)
                    : interpolate(from: spec.start, to: spec.end, progress: progress)
                generateDay(
                    day,
                    profile: profile,
                    spec: spec,
                    isSkipped: isSkipped,
                    targets: targets,
                    context: context,
                    calendar: calendar
                )
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
        isSkipped: Bool,
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

        // 排便が 1 件もない日は「排便なし」として残す。ここを立てないと未記録の日と区別できず、
        // 0 回として集計に入らない。まとめ自体は毎日は書かれない想定にして実際の使われ方に近づける。
        let hadNoBowelMovement = count == 0
        if hadNoBowelMovement || Int.random(in: 0...3, using: &generator) > 0 {
            let condition: ConditionLevel = count >= 4 ? .poor : (count >= 3 ? .fair : .good)
            let record = DailyRecord(
                date: day,
                overallCondition: condition,
                abdominalCondition: profile.pain.upperBound >= 2 ? .fair : .good,
                hadNoBowelMovement: hadNoBowelMovement,
                calendar: calendar
            )
            context.insert(record)
        }

        for name in spec.targetNames {
            guard let target = targets[name] else { continue }
            // 未実施の日も行は残す。行がないと「記録していない日」になってしまう。
            let record = TargetRecord(date: day, target: target, isCompleted: !isSkipped, calendar: calendar)
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
            DailyRecord.self, TargetRecord.self, TargetAttachment.self, BowelMovement.self,
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

    /// 書き出し画面と紙面のプレビュー用。サンプルデータをそのまま報告の形にしたもの。
    @MainActor
    static var previewReport: ObservationReport {
        let context = previewContainer.mainContext
        let plan = previewPlan
        return ObservationReport.make(
            plan: plan,
            movements: (try? context.fetch(FetchDescriptor<BowelMovement>())) ?? [],
            dailyRecords: (try? context.fetch(FetchDescriptor<DailyRecord>())) ?? [],
            targetRecords: (try? context.fetch(FetchDescriptor<TargetRecord>())) ?? [],
            range: plan.observedRange() ?? Date.now...Date.now
        )
    }

    /// 記録が 1 件もない状態のプレビュー用コンテナ。
    @MainActor
    static let emptyPreviewContainer: ModelContainer = {
        try! ModelContainer(
            for: ObservationPlan.self, ObservationPhase.self, ObservationTarget.self,
            DailyRecord.self, TargetRecord.self, TargetAttachment.self, BowelMovement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }()
}
#endif
