import Foundation
import SwiftData

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

    var id: Date { date }

    /// 記録が付いた日かどうか。
    /// まとめだけ書かれた日は「排便 0 回」として扱い、何も書かれていない日は集計から外す。
    /// 未記録を 0 と数えると平均が実態より低く出てしまうため。
    var hasRecord: Bool { bowelCount > 0 || hasSummary }
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
    /// そのうち実際に記録が付いた日数。平均の分母はこちら。
    var recordedDays: Int

    var totalBowelCount: Int
    var averageBowelCount: Double?
    var averageBristol: Double?
    var averagePain: Double?
    var averageUrgency: Double?

    var id: PersistentIdentifier { phaseID }
    var isOngoing: Bool { endDate == nil }
    var hasEnoughData: Bool { recordedDays > 0 }
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
        case .bowelCount: tally.hasRecord ? Double(tally.bowelCount) : nil
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
}

/// 指標 1 つ分の変化。数値と向きだけを持ち、評価はしない。
struct MetricChange: Identifiable, Sendable {
    var metric: ObservationMetric
    var subject: Double
    var reference: Double

    var id: String { metric.rawValue }
    var delta: Double { subject - reference }

    /// 変化率。基準が 0 のときは割合を出せないので nil。
    var ratio: Double? {
        guard reference != 0 else { return nil }
        return delta / abs(reference)
    }

    var isIncrease: Bool { delta > 0 }

    /// 事実だけを述べた一文。効いている／合っているといった判断は含めない。
    func sentence(referenceName: String) -> String {
        let rounded = (delta * 10).rounded() / 10
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

    func change(for metric: ObservationMetric) -> MetricChange? {
        changes.first { $0.metric == metric }
    }
}
