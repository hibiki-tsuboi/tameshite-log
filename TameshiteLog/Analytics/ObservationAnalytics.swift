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

    /// 画面に出す小数第 1 位にそろえたあとの変化方向。
    ///
    /// 画面では 0.04 を「0」と表示するため、生の値だけで増減を決めると
    /// 「差は 0 なのに増えた」といった食い違いが起きる。再現性チェックも
    /// 利用者が読んでいる数値と同じ丸め方で方向を判定する。
    var recordedDirection: RecordedChangeDirection {
        let rounded = (delta * 10).rounded() / 10
        if rounded > 0 { return .increase }
        if rounded < 0 { return .decrease }
        return .unchanged
    }

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
            guard round.meetsMinimum else { return nil }
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
