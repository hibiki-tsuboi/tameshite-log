import SwiftUI

/// 紙面の寸法。A4 を 72dpi（PDF の 1pt = 1/72 インチ）で表したもの。
enum ReportLayout {
    static let pageSize = CGSize(width: 595, height: 842)
    static let margin: CGFloat = 40
    static let footerHeight: CGFloat = 22

    static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    static var contentHeight: CGFloat { pageSize.height - margin * 2 - footerHeight }
}

/// 紙面で使う文字の大きさ。ダイナミックタイプに追従させると紙面が崩れるので、
/// 画面用の意味づけされたフォントではなく実寸で指定する。
private enum ReportFont {
    static let title = Font.system(size: 20, weight: .bold)
    static let section = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 10)
    static let caption = Font.system(size: 8.5)
    static let tableHead = Font.system(size: 8.5, weight: .semibold)
    static let table = Font.system(size: 8.5)
    static let tableNumber = Font.system(size: 8.5).monospacedDigit()
}

/// 1 ページに何を載せるか。中身の量で決まるので `ReportPagination` が組み立てる。
enum ReportPage: Hashable {
    case overview(Range<Int>, includesHeader: Bool)
    case charts([ObservationMetric])
    case days(Range<Int>)
    case notes(Range<Int>)
}

/// ページ分割。表は行の高さが決まっているので件数で割り切れる。
/// メモだけは長さが読めないため、見積もりを多めに取って詰め込みすぎないようにする。
enum ReportPagination {
    static let phasesPerPage = 6
    static let chartsPerPage = 4
    static let daysPerPage = 42

    static func pages(for report: ObservationReport) -> [ReportPage] {
        var pages: [ReportPage] = []

        if report.summaries.isEmpty {
            pages.append(.overview(0..<0, includesHeader: true))
        } else {
            for start in stride(from: 0, to: report.summaries.count, by: phasesPerPage) {
                let end = min(start + phasesPerPage, report.summaries.count)
                pages.append(.overview(start..<end, includesHeader: start == 0))
            }
        }

        let metrics = report.chartableMetrics
        for start in stride(from: 0, to: metrics.count, by: chartsPerPage) {
            pages.append(.charts(Array(metrics[start..<min(start + chartsPerPage, metrics.count)])))
        }

        for start in stride(from: 0, to: report.days.count, by: daysPerPage) {
            pages.append(.days(start..<min(start + daysPerPage, report.days.count)))
        }

        var index = 0
        while index < report.notes.count {
            var used: CGFloat = 30
            var end = index
            while end < report.notes.count {
                let next = estimatedHeight(report.notes[end])
                if end > index, used + next > ReportLayout.contentHeight { break }
                used += next
                end += 1
            }
            pages.append(.notes(index..<end))
            index = end
        }

        return pages
    }

    private static func estimatedHeight(_ note: ObservationReport.NoteEntry) -> CGFloat {
        let charactersPerLine = 34.0
        let lines = max(1, (Double(note.text.count) / charactersPerLine).rounded(.up))
        return CGFloat(lines) * 13 + 9
    }
}

/// PDF 1 ページ分。`ImageRenderer` にそのまま渡すので、画面用の装飾は使わない。
struct ReportPageView: View {
    var report: ObservationReport
    var page: ReportPage
    var pageNumber: Int
    var pageCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(ReportLayout.margin)
        .frame(width: ReportLayout.pageSize.width, height: ReportLayout.pageSize.height, alignment: .topLeading)
        .background(.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
        .environment(\.locale, Formatting.locale)
        .environment(\.dynamicTypeSize, .large)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case let .overview(range, includesHeader):
            VStack(alignment: .leading, spacing: 18) {
                if includesHeader { header }
                phaseTable(Array(report.summaries[range]))
                comparisonTable(Array(report.summaries[range]))
                basisNote
            }

        case let .charts(metrics):
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("推移")
                ForEach(metrics) { metric in chartBlock(metric) }
            }

        case let .days(range):
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("日別の記録")
                dayTable(Array(report.days[range]))
            }

        case let .notes(range):
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("メモ")
                noteList(Array(report.notes[range]))
            }
        }
    }

    // MARK: - 見出しと注記

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ためしてログ ・ 記録の書き出し")
                .font(ReportFont.caption)
                .foregroundStyle(.secondary)

            Text(report.planName)
                .font(ReportFont.title)

            Text(periodLine)
                .font(ReportFont.body)

            Text("\(Formatting.mediumDate(report.generatedAt)) 出力")
                .font(ReportFont.caption)
                .foregroundStyle(.secondary)

            notice
                .padding(.top, 7)
        }
    }

    private var periodLine: String {
        let period = "\(Formatting.mediumDate(report.range.lowerBound)) 〜 \(Formatting.mediumDate(report.range.upperBound))"
        return "\(period) ・ \(report.elapsedDays)日間（記録 \(report.recordedDays)日）・ 排便 \(report.totalBowelCount)件"
    }

    private var notice: some View {
        Text("このシートは、アプリに記録した内容を集計したものです。診断や治療方針を示すものではありません。")
            .font(ReportFont.caption)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.black.opacity(0.25), lineWidth: 0.7)
            )
    }

    private var basisNote: some View {
        Text(basisText)
            .font(ReportFont.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var basisText: String {
        var text = "平均の分母は記録がある日数です。記録のない日は「0 回」ではなく集計から外しています。「排便なし」と記録された日だけを 0 回として数えています。フェーズ別の集計は、期間の一部だけを書き出した場合もフェーズ全体の記録から計算しています。"
        if report.hasWarmupExclusion {
            text += "開始直後を集計から外す設定のフェーズでは、その日数ぶんを平均と比較から除いています。除いた日の記録は残っています。"
        }
        return text
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(ReportFont.section)
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Text("ためしてログ ・ \(report.planName)")
            Spacer(minLength: 8)
            Text("\(pageNumber) / \(pageCount)")
        }
        .font(ReportFont.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: ReportLayout.footerHeight, alignment: .bottom)
    }

    // MARK: - フェーズ別の集計

    private let phaseWidths: [CGFloat] = [170, 100, 65, 55, 42, 42, 41]
    private let phaseAlignments: [Alignment] = [.leading, .leading, .center, .trailing, .trailing, .trailing, .trailing]

    @ViewBuilder
    private func phaseTable(_ summaries: [PhaseSummary]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("フェーズ別の集計")

            if summaries.isEmpty {
                Text(report.hasRecords ? "この期間に重なるフェーズはありません。" : "この期間に記録はありません。")
                    .font(ReportFont.body)
                    .foregroundStyle(.secondary)
            } else {
                tableHeader(
                    ["フェーズ", "期間", "日数（記録）", "平均排便回数", "便の形", "腹痛", "便意"],
                    widths: phaseWidths,
                    alignments: phaseAlignments
                )
                ForEach(summaries) { summary in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 0) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(color(for: summary))
                                    .frame(width: 6, height: 6)
                                Text(summary.name)
                                    .font(ReportFont.table)
                                    .lineLimit(1)
                            }
                            .frame(width: phaseWidths[0], alignment: .leading)

                            cell(Formatting.dateRange(from: summary.startDate, to: summary.endDate), width: phaseWidths[1], alignment: .leading)
                            cell("\(summary.elapsedDays)日（\(summary.recordedDays)日）", width: phaseWidths[2], alignment: .center)
                            cell(value(.bowelCount, in: summary), width: phaseWidths[3], alignment: .trailing, numeric: true)
                            cell(value(.bristol, in: summary), width: phaseWidths[4], alignment: .trailing, numeric: true)
                            cell(value(.abdominalPain, in: summary), width: phaseWidths[5], alignment: .trailing, numeric: true)
                            cell(value(.urgency, in: summary), width: phaseWidths[6], alignment: .trailing, numeric: true)
                        }

                        if let detail = detail(for: summary) {
                            Text(detail)
                                .font(ReportFont.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.leading, 11)
                        }
                    }
                    .padding(.vertical, 3)
                    Divider().opacity(0.4)
                }
            }
        }
    }

    // MARK: - いつもの状態との差

    private let changeWidths: [CGFloat] = [170, 90, 85, 85, 85]

    @ViewBuilder
    private func comparisonTable(_ summaries: [PhaseSummary]) -> some View {
        let ids = Set(summaries.map(\.id))
        let comparisons = report.comparisons.filter { ids.contains($0.subject.id) }

        if !comparisons.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                sectionTitle(comparisons.first?.kind.label ?? "比較")

                tableHeader(
                    ["フェーズ", "平均排便回数", "便の形", "腹痛", "便意"],
                    widths: changeWidths,
                    alignments: [.leading, .trailing, .trailing, .trailing, .trailing]
                )

                ForEach(comparisons) { comparison in
                    HStack(spacing: 0) {
                        Text(comparison.subject.name)
                            .font(ReportFont.table)
                            .lineLimit(1)
                            .frame(width: changeWidths[0], alignment: .leading)
                        cell(delta(.bowelCount, in: comparison), width: changeWidths[1], alignment: .trailing, numeric: true)
                        cell(delta(.bristol, in: comparison), width: changeWidths[2], alignment: .trailing, numeric: true)
                        cell(delta(.abdominalPain, in: comparison), width: changeWidths[3], alignment: .trailing, numeric: true)
                        cell(delta(.urgency, in: comparison), width: changeWidths[4], alignment: .trailing, numeric: true)
                    }
                    .padding(.vertical, 3)
                    Divider().opacity(0.4)
                }

                if let reference = comparisons.first?.reference.name {
                    Text("「\(reference)」との差です。かっこ内は変化率。")
                        .font(ReportFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 推移

    private func chartBlock(_ metric: ObservationMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title)
                .font(ReportFont.body)
            PhaseTimelineChart(
                tallies: report.tallies,
                summaries: report.summaries,
                metric: metric,
                color: { color(for: $0) },
                dateDomain: chartDomain,
                height: 145
            )
            .font(ReportFont.caption)
        }
    }

    private var chartDomain: ClosedRange<Date> {
        report.range.lowerBound.addingTimeInterval(-43_200)...report.range.upperBound.addingTimeInterval(43_200)
    }

    // MARK: - 日別の記録

    private let dayWidths: [CGFloat] = [46, 20, 78, 34, 42, 34, 34, 34, 34, 159]

    private func dayTable(_ days: [ObservationReport.DayRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            tableHeader(
                ["日付", "曜", "フェーズ", "回数", "便の形", "腹痛", "便意", "体調", "腹部", "実施した観察対象"],
                widths: dayWidths,
                alignments: [.leading, .center, .leading, .trailing, .trailing, .trailing, .trailing, .center, .center, .leading]
            )

            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 0) {
                    cell(Formatting.shortDate(day.date), width: dayWidths[0], alignment: .leading)
                    cell(weekday(day.date), width: dayWidths[1], alignment: .center)
                    cell(day.phaseName, width: dayWidths[2], alignment: .leading)
                    cell(day.hasRecord ? "\(day.tally.bowelCount)" : "—", width: dayWidths[3], alignment: .trailing, numeric: true)
                    cell(optional(day.tally.averageBristol), width: dayWidths[4], alignment: .trailing, numeric: true)
                    cell(optional(day.tally.averagePain), width: dayWidths[5], alignment: .trailing, numeric: true)
                    cell(optional(day.tally.averageUrgency), width: dayWidths[6], alignment: .trailing, numeric: true)
                    cell(day.tally.overallCondition?.label ?? "", width: dayWidths[7], alignment: .center)
                    cell(day.tally.abdominalCondition?.label ?? "", width: dayWidths[8], alignment: .center)
                    cell(day.completedTargets.joined(separator: " / "), width: dayWidths[9], alignment: .leading)
                }
                .frame(height: 15)
                .background(index.isMultiple(of: 2) ? Color.black.opacity(0.035) : .clear)
                .foregroundStyle(day.hasRecord ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
    }

    // MARK: - メモ

    private func noteList(_ notes: [ObservationReport.NoteEntry]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(notes) { note in
                HStack(alignment: .top, spacing: 10) {
                    Text(label(for: note))
                        .font(ReportFont.table)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 96, alignment: .leading)
                    Text(note.text)
                        .font(ReportFont.body)
                        .lineLimit(28)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func label(for note: ObservationReport.NoteEntry) -> String {
        guard let time = note.time else { return "\(Formatting.shortDate(note.date)) まとめ" }
        return "\(Formatting.shortDate(note.date)) \(Formatting.time(time))"
    }

    // MARK: - 表の部品

    private func tableHeader(_ titles: [String], widths: [CGFloat], alignments: [Alignment]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    Text(title)
                        .font(ReportFont.tableHead)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: widths[index], alignment: alignments[index])
                }
            }
            .frame(height: 16)
            Divider().overlay(Color.black.opacity(0.4))
        }
    }

    private func cell(_ text: String, width: CGFloat, alignment: Alignment, numeric: Bool = false) -> some View {
        Text(text)
            .font(numeric ? ReportFont.tableNumber : ReportFont.table)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    // MARK: -

    /// フェーズ名がそのまま種類名になっている場合は種類を省く。同じ言葉が二度並ぶだけなので。
    private func detail(for summary: PhaseSummary) -> String? {
        var parts: [String] = []
        if summary.name != summary.type.label { parts.append(summary.type.label) }
        if summary.targetSummary != "観察対象なし" { parts.append(summary.targetSummary) }
        if let adherence = adherenceText(for: summary) { parts.append(adherence) }
        if summary.warmupDays > 0 { parts.append("最初の\(summary.warmupDays)日を除外") }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }

    /// 実施した日数を並べる。割合にはしない。チェックのない日は「実施していない」ではなく
    /// 「記録していない」なので、率にすると実態から離れる。
    private func adherenceText(for summary: PhaseSummary) -> String? {
        guard !summary.adherence.isEmpty else { return nil }
        if summary.adherence.count == 1, let item = summary.adherence.first {
            return "実施 \(item.completedDays)/\(item.analyzedDays)日"
        }
        return summary.adherence
            .map { "\($0.name) \($0.completedDays)/\($0.analyzedDays)日" }
            .joined(separator: " ・ ")
    }

    private func value(_ metric: ObservationMetric, in summary: PhaseSummary) -> String {
        guard let value = metric.value(in: summary) else { return "—" }
        return Formatting.decimal(value)
    }

    /// 差と変化率をひとつのセルに収める。単位は列見出しに任せる。
    private func delta(_ metric: ObservationMetric, in comparison: PhaseComparison) -> String {
        guard let change = comparison.change(for: metric) else { return "—" }
        let rounded = (change.delta * 10).rounded() / 10
        guard rounded != 0 else { return "±0" }
        guard let ratio = change.ratio else { return Formatting.signedDecimal(rounded) }
        return "\(Formatting.signedDecimal(rounded))（\(Formatting.signedPercent(ratio))）"
    }

    private func optional(_ value: Double?) -> String {
        guard let value else { return "" }
        return Formatting.decimal(value)
    }

    private func weekday(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow).locale(Formatting.locale))
    }

    private func color(for summary: PhaseSummary) -> Color {
        PhasePalette.color(type: summary.type, index: report.phaseColorIndices[summary.id] ?? 0)
    }
}

#if DEBUG
/// 紙面をまとめて確かめるためのプレビュー用ビュー。
private struct ReportPagesPreview: View {
    var report = SampleData.previewReport

    var body: some View {
        let pages = ReportPagination.pages(for: report)
        ScrollView {
            VStack(spacing: 24) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    ReportPageView(report: report, page: page, pageNumber: index + 1, pageCount: pages.count)
                        .border(Color.gray.opacity(0.5))
                }
            }
            .scaleEffect(0.62, anchor: .top)
            .frame(height: CGFloat(pages.count) * (ReportLayout.pageSize.height + 24) * 0.62)
        }
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    ReportPagesPreview()
}
#endif
