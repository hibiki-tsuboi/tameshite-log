import Foundation
import SwiftData

/// 集計をどこまで言葉にするかの線引き。
///
/// 数値そのものは記録があれば出せるが、「減っています」と文章にするには
/// 日々のばらつきと区別できるだけの日数が要る。その閾値をここに集める。
enum AnalysisBasis {
    /// 差を文章にするために、両側にそろえたい記録日数。
    /// これを下回るときは差の数値だけを出し、断定した一文は出さない。
    static let minimumComparisonDays = 7
}

/// 1 日分に畳み込んだ記録。グラフの 1 点にあたる。
struct DailyTally: Identifiable, Hashable, Sendable {
    var date: Date
    var bowelCount: Int
    var averageBristol: Double?
    var averagePain: Double?
    var averageUrgency: Double?
    var overallCondition: ConditionLevel?
    var abdominalCondition: ConditionLevel?
    var hasSummary: Bool
    /// 「排便なし」と明示された日。表示で 0 回と未記録を描き分けるために持つ。
    var hadNoBowelMovement: Bool

    var id: Date { date }

    /// その日に何か書かれたかどうか。日数の表示と、記録のある日の数え上げに使う。
    ///
    /// 「排便なし」は `DailyRecord.isEmpty` を false にするので `hasSummary` に含まれる。
    var hasRecord: Bool { bowelCount > 0 || hasSummary }

    /// 排便回数が分かっている日かどうか。平均排便回数の分母はこちら。
    ///
    /// 体調やメモだけ書いた日を 0 回と数えない。その日は排便がなかったのかもしれないし、
    /// 書き忘れただけかもしれず、記録からはどちらとも言えないため。
    /// 0 回として数えてよいのは、本人が「排便なし」と書いた日だけ。
    var hasBowelCount: Bool { bowelCount > 0 || hadNoBowelMovement }

    /// 便の形・腹痛・急な便意の平均に寄与する日。これらは排便 1 件ごとに記録される。
    var hasMovementMetrics: Bool { bowelCount > 0 }
}

/// 指標 1 つ分のばらつき。
///
/// 平均だけだと、差が日々の振れ幅の内側なのか外側なのか読めない。
/// 判断はしないが、読み手が自分で判断できる材料としてこれを並べる。
struct MetricSpread: Sendable {
    var minimum: Double
    var maximum: Double

    var isFlat: Bool { minimum == maximum }
}

/// 観察対象 1 つの、フェーズ内での実施状況。
///
/// 割合は出さない。チェックが付いていない日は「実施していない」ではなく
/// 「記録していない」なので、そこを埋めた率にすると実態より高くも低くも振れる。
/// 実施した日数と集計日数をそのまま並べて、読み手に判断を残す。
struct TargetAdherence: Identifiable, Sendable {
    var targetID: PersistentIdentifier
    var name: String
    /// 実施したと記録した日数。
    var completedDays: Int
    /// 実施しなかったと明示して記録した日数。
    var skippedDays: Int
    /// 集計対象の日数（分母）。
    var analyzedDays: Int

    var id: PersistentIdentifier { targetID }

    /// どちらとも記録されていない日数。
    var untrackedDays: Int { max(0, analyzedDays - completedDays - skippedDays) }
}

/// フェーズ単位の集計結果。
struct PhaseSummary: Identifiable, Sendable {
    var phaseID: PersistentIdentifier
    var name: String
    var type: PhaseType
    var startDate: Date
    var endDate: Date?
    var effectiveEndDate: Date
    var targetSummary: String

    /// フェーズが何日続いたか（今日で打ち切り）。
    var elapsedDays: Int
    /// そのうち実際に記録が付いた日数。期間の説明に使う。
    var recordedDays: Int
    /// 集計から外した、開始直後の日数。
    var warmupDays: Int
    /// 立ち上がりを外したあとの、集計対象になる日数。
    var analyzedDays: Int

    var averageBowelCount: Double?
    var averageBristol: Double?
    var averagePain: Double?
    var averageUrgency: Double?
    /// 指標ごとの最小・最大。平均に添えてばらつきを示すために持つ。
    var spreads: [ObservationMetric: MetricSpread]
    /// フェーズに紐づいた観察対象の実施状況。
    var adherence: [TargetAdherence]

    /// 指標ごとの、平均の根拠になった日数。
    ///
    /// `recordedDays` とは別に持つ。平均排便回数の分母は「排便回数が分かっている日」で、
    /// 便の形・腹痛・便意の分母は「排便が 1 件でもあった日」なので、指標ごとに違う。
    /// 「排便なし」の日が多い観察では、記録 10 日でも便の形は 1 日ぶんしかない、が普通に起きる。
    var metricRecordedDays: [ObservationMetric: Int]

    var id: PersistentIdentifier { phaseID }
    var hasEnoughData: Bool { recordedDays > 0 }

    /// その指標の平均が、何日ぶんの記録から出ているか。
    func recordedDays(for metric: ObservationMetric) -> Int { metricRecordedDays[metric] ?? 0 }

    /// その指標の差を文章にしてよいだけの日数がそろっているか。
    ///
    /// 指標ごとに見る。`recordedDays` で一括に判定すると、記録日数だけは足りていて
    /// その指標のサンプルが 1 件しかない期間でも断定した一文が出てしまう。
    func meetsComparisonMinimum(for metric: ObservationMetric) -> Bool {
        recordedDays(for: metric) >= AnalysisBasis.minimumComparisonDays
    }

    /// 立ち上がりの除外がフェーズ全体を飲み込んでしまった状態。
    /// 「記録がない」のとは理由が違うので、画面で書き分けられるように分けておく。
    var isFullyExcludedByWarmup: Bool { warmupDays > 0 && analyzedDays <= 0 }

    func spread(for metric: ObservationMetric) -> MetricSpread? { spreads[metric] }
}

/// 比較できる指標。グラフと集計カードで同じ定義を使う。
enum ObservationMetric: String, CaseIterable, Identifiable, Sendable {
    case bowelCount
    case bristol
    case abdominalPain
    case urgency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bowelCount: "排便回数"
        case .bristol: "ブリストル値"
        case .abdominalPain: "腹痛"
        case .urgency: "急な便意"
        }
    }

    /// セグメント切り替え用の短い名前。
    var shortTitle: String {
        switch self {
        case .bowelCount: "回数"
        case .bristol: "便の形"
        case .abdominalPain: "腹痛"
        case .urgency: "便意"
        }
    }

    var averageTitle: String {
        switch self {
        case .bowelCount: "平均排便回数"
        case .bristol: "平均ブリストル値"
        case .abdominalPain: "腹痛平均"
        case .urgency: "急な便意平均"
        }
    }

    var unit: String {
        switch self {
        case .bowelCount: "回/日"
        default: ""
        }
    }

    var axisLabel: String {
        switch self {
        case .bowelCount: "回"
        case .bristol: "1〜7"
        case .abdominalPain, .urgency: "0〜3"
        }
    }

    /// Y 軸の固定範囲。回数だけはデータに合わせて伸ばすので nil。
    var axisDomain: ClosedRange<Double>? {
        switch self {
        case .bowelCount: nil
        case .bristol: 1...7
        case .abdominalPain, .urgency: 0...3
        }
    }

    /// 増減を言葉にするときの対（増えた側 / 減った側）。
    var comparativeWords: (increase: String, decrease: String) {
        switch self {
        case .bowelCount: ("多く", "少なく")
        case .bristol, .abdominalPain, .urgency: ("高く", "低く")
        }
    }

    func value(in tally: DailyTally) -> Double? {
        switch self {
        case .bowelCount: tally.hasBowelCount ? Double(tally.bowelCount) : nil
        case .bristol: tally.averageBristol
        case .abdominalPain: tally.averagePain
        case .urgency: tally.averageUrgency
        }
    }

    func value(in summary: PhaseSummary) -> Double? {
        switch self {
        case .bowelCount: summary.averageBowelCount
        case .bristol: summary.averageBristol
        case .abdominalPain: summary.averagePain
        case .urgency: summary.averageUrgency
        }
    }

    func formatted(_ value: Double) -> String {
        Formatting.decimal(value) + unit
    }

    func formattedDelta(_ value: Double) -> String {
        Formatting.signedDecimal(value) + unit
    }

    /// 「1〜7回」。平均に添えて振れ幅を示すための短い表記。
    func formattedSpread(_ spread: MetricSpread) -> String {
        guard !spread.isFlat else { return formatted(spread.minimum) }
        return "\(Formatting.decimal(spread.minimum))〜\(Formatting.decimal(spread.maximum))\(unit)"
    }
}

/// 指標 1 つ分の変化。数値と向きだけを持ち、評価はしない。
struct MetricChange: Identifiable, Sendable {
    var metric: ObservationMetric
    var subject: Double
    var reference: Double

    var id: String { metric.rawValue }
    var delta: Double { subject - reference }

    /// 画面にも紙面にも、差はこの丸めた値で出る。向きと変化率もここから決める。
    var roundedDelta: Double { (delta * 10).rounded() / 10 }

    /// 変化率。基準が 0 のときは割合を出せないので nil。
    ///
    /// 丸めた差から出す。生の差で割ると、差が「0」と表示されている横に「-4%」が並び、
    /// 同じ箱の中で数字と割合が食い違う。読み手が見ている数どうしの比にする。
    /// 丸めて 0 になる差に割合はないので、そのときも nil。
    var ratio: Double? {
        let rounded = roundedDelta
        guard rounded != 0, reference != 0 else { return nil }
        return rounded / abs(reference)
    }

    /// 画面に出す小数第 1 位にそろえたあとの変化方向。
    ///
    /// 画面では 0.04 を「0」と表示するため、生の値だけで増減を決めると
    /// 「差は 0 なのに増えた」といった食い違いが起きる。再現性チェックも
    /// 利用者が読んでいる数値と同じ丸め方で方向を判定する。
    var recordedDirection: RecordedChangeDirection {
        let rounded = roundedDelta
        if rounded > 0 { return .increase }
        if rounded < 0 { return .decrease }
        return .unchanged
    }

    /// 事実だけを述べた一文。効いている／合っているといった判断は含めない。
    func sentence(referenceName: String) -> String {
        let rounded = roundedDelta
        guard rounded != 0 else {
            return "「\(referenceName)」と比べて、\(metric.averageTitle)は変わっていません。"
        }
        let word = rounded > 0 ? metric.comparativeWords.increase : metric.comparativeWords.decrease
        let amount = Formatting.decimal(abs(rounded)) + metric.unit
        if let ratio {
            return "記録上、「\(referenceName)」と比べて\(metric.averageTitle)が\(amount) \(word)なっています（\(Formatting.signedPercent(ratio))）。"
        }
        return "記録上、「\(referenceName)」と比べて\(metric.averageTitle)が\(amount) \(word)なっています。"
    }
}

/// 記録上の変化方向。良い／悪い、効いた／効かなかったという評価は持たない。
enum RecordedChangeDirection: Hashable, Sendable {
    case increase
    case decrease
    case unchanged
}

/// フェーズ同士の比較。
struct PhaseComparison: Identifiable, Sendable {
    enum Reference: String, Sendable {
        case baseline
        case previous

        var label: String {
            switch self {
            case .baseline: "いつもの状態と比較"
            case .previous: "直前の期間と比較"
            }
        }
    }

    var subject: PhaseSummary
    var reference: PhaseSummary
    var kind: Reference
    var changes: [MetricChange]

    var id: String { "\(subject.id)-\(kind.rawValue)" }

    /// その指標について、両側に十分な日数があるか。
    /// 片側でも足りなければ、差の数値は出しても断定した一文は出さない。
    func meetsMinimum(for metric: ObservationMetric) -> Bool {
        subject.meetsComparisonMinimum(for: metric) && reference.meetsComparisonMinimum(for: metric)
    }

    /// 足りていない側の日数。画面で「あと何日ぶんか」を書くために使う。
    func thinnerSideDays(for metric: ObservationMetric) -> Int {
        min(subject.recordedDays(for: metric), reference.recordedDays(for: metric))
    }

    func change(for metric: ObservationMetric) -> MetricChange? {
        changes.first { $0.metric == metric }
    }
}

/// 同じ観察対象を含む複数の「試している期間」を、各回の直前にある
/// いつもの状態／お休み期間と見くらべた結果。
///
/// 永続化はしない。既存のフェーズと記録から都度計算するため、モデル移行は不要。
struct ReproducibilityCheck: Identifiable, Sendable {
    /// この組み合わせが最初に現れたフェーズ。1 フェーズは 1 組にしか属さないため ID に使える。
    var firstPhaseID: PersistentIdentifier
    var targetNames: [String]
    /// 同じ観察対象の組み合わせを持つ期間の総数。比較できない期間も含む。
    var phaseCount: Int
    /// 直前の基準期間と比較できた各回。日数不足の比較も含む。
    var rounds: [PhaseComparison]

    var id: PersistentIdentifier { firstPhaseID }
    var title: String { targetNames.joined(separator: " + ") }

    /// 選択中の指標について、両側に最低日数がそろった比較だけを返す。
    func comparableChanges(for metric: ObservationMetric) -> [MetricChange] {
        rounds.compactMap { round in
            guard round.meetsMinimum(for: metric) else { return nil }
            return round.change(for: metric)
        }
    }

    /// 2 回以上比較できたとき、最も多かった方向とその回数を返す。
    /// 同数なら方向を 1 つに決めず nil にして、画面では「方向が分かれた」と表示する。
    func result(for metric: ObservationMetric) -> ReproducibilityResult? {
        let changes = comparableChanges(for: metric)
        guard changes.count >= 2 else { return nil }

        let counts = Dictionary(grouping: changes, by: \.recordedDirection)
            .mapValues(\.count)
        let ranked = counts.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return directionOrder(lhs.key) < directionOrder(rhs.key)
            }
            return lhs.value > rhs.value
        }
        let top = ranked[0]
        let hasUniqueTop = ranked.dropFirst().first.map { top.value > $0.value } ?? true

        return ReproducibilityResult(
            comparableRounds: changes.count,
            dominantDirection: hasUniqueTop ? top.key : nil,
            matchingRounds: hasUniqueTop ? top.value : 0
        )
    }

    private func directionOrder(_ direction: RecordedChangeDirection) -> Int {
        switch direction {
        case .decrease: 0
        case .unchanged: 1
        case .increase: 2
        }
    }
}

struct ReproducibilityResult: Sendable {
    var comparableRounds: Int
    var dominantDirection: RecordedChangeDirection?
    var matchingRounds: Int
}

/// 同じフェーズの中で「実施した日」と「実施しなかった日」を見くらべたもの。
///
/// フェーズ同士の比較と違って、季節も生活も同じ本人の同じ期間なので、
/// 期間の違いが混ざりこまない。飲み忘れのある観察ほどここに情報が出る。
/// どちらとも記録していない日は、どちらにも入れない。
struct AdherenceComparison: Identifiable, Sendable {
    var phaseID: PersistentIdentifier
    var targetID: PersistentIdentifier
    var targetName: String
    /// 実施した側の、指標ごとの記録日数。
    ///
    /// 側ごとの合計ではなく指標ごとに持つ。実施した日が 14 日あっても、
    /// そのうち排便があったのが 3 日なら、便の形の平均は 3 日ぶんでしかない。
    var metricCompletedDays: [ObservationMetric: Int]
    /// 実施しなかった側の、指標ごとの記録日数。
    var metricSkippedDays: [ObservationMetric: Int]
    var changes: [MetricChange]

    var id: String { "\(phaseID)-\(targetID)" }

    static let completedLabel = "実施した日"
    static let skippedLabel = "実施しなかった日"

    /// その指標の平均が、実施した側で何日ぶんの記録から出ているか。
    func completedDays(for metric: ObservationMetric) -> Int { metricCompletedDays[metric] ?? 0 }
    /// その指標の平均が、実施しなかった側で何日ぶんの記録から出ているか。
    func skippedDays(for metric: ObservationMetric) -> Int { metricSkippedDays[metric] ?? 0 }

    func meetsMinimum(for metric: ObservationMetric) -> Bool {
        completedDays(for: metric) >= AnalysisBasis.minimumComparisonDays
            && skippedDays(for: metric) >= AnalysisBasis.minimumComparisonDays
    }

    func thinnerSideDays(for metric: ObservationMetric) -> Int {
        min(completedDays(for: metric), skippedDays(for: metric))
    }

    func change(for metric: ObservationMetric) -> MetricChange? {
        changes.first { $0.metric == metric }
    }
}
