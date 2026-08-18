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

    /// 記録が付いた日かどうか。
    /// まとめだけ書かれた日は「排便 0 回」として扱い、何も書かれていない日は集計から外す。
    /// 未記録を 0 と数えると平均が実態より低く出てしまうため。
    ///
    /// 「排便なし」は `DailyRecord.isEmpty` を false にするので `hasSummary` に含まれる。
    var hasRecord: Bool { bowelCount > 0 || hasSummary }
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
    /// そのうち実際に記録が付いた日数。平均の分母はこちら。
    var recordedDays: Int
    /// 集計から外した、開始直後の日数。
    var warmupDays: Int
    /// 立ち上がりを外したあとの、集計対象になる日数。
    var analyzedDays: Int

    var totalBowelCount: Int
    var averageBowelCount: Double?
    var averageBristol: Double?
    var averagePain: Double?
    var averageUrgency: Double?
    /// 指標ごとの最小・最大。平均に添えてばらつきを示すために持つ。
    var spreads: [ObservationMetric: MetricSpread]
    /// フェーズに紐づいた観察対象の実施状況。
    var adherence: [TargetAdherence]

    var id: PersistentIdentifier { phaseID }
    var isOngoing: Bool { endDate == nil }
    var hasEnoughData: Bool { recordedDays > 0 }

    /// 差を文章にしてよいだけの日数がそろっているか。
    var meetsComparisonMinimum: Bool { recordedDays >= AnalysisBasis.minimumComparisonDays }

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

    /// 両側に十分な日数があるか。片側でも足りなければ、差の数値は出しても断定した一文は出さない。
    var meetsMinimum: Bool {
        subject.meetsComparisonMinimum && reference.meetsComparisonMinimum
    }

    /// 足りていない側の日数。画面で「あと何日ぶんか」を書くために使う。
    var thinnerSideDays: Int { min(subject.recordedDays, reference.recordedDays) }

    func change(for metric: ObservationMetric) -> MetricChange? {
        changes.first { $0.metric == metric }
    }
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
    /// 実施したと記録した日のうち、記録が付いた日数。
    var completedDays: Int
    /// 実施しなかったと記録した日のうち、記録が付いた日数。
    var skippedDays: Int
    var changes: [MetricChange]

    var id: String { "\(phaseID)-\(targetID)" }

    static let completedLabel = "実施した日"
    static let skippedLabel = "実施しなかった日"

    var meetsMinimum: Bool {
        completedDays >= AnalysisBasis.minimumComparisonDays
            && skippedDays >= AnalysisBasis.minimumComparisonDays
    }

    var thinnerSideDays: Int { min(completedDays, skippedDays) }

    func change(for metric: ObservationMetric) -> MetricChange? {
        changes.first { $0.metric == metric }
    }
}
