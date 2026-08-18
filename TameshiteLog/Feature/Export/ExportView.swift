import SwiftUI
import SwiftData

/// 書き出す範囲の選び方。
enum ExportPeriod: String, CaseIterable, Identifiable {
    case plan
    case recent30
    case recent90
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plan: "プラン全体"
        case .recent30: "直近30日"
        case .recent90: "直近90日"
        case .custom: "期間を指定"
        }
    }
}

/// 記録の書き出し。PDF は人に見せる用、CSV は控えと表計算用。
///
/// 数値の出どころは経過画面とまったく同じ（`ObservationAnalyzer`）にしてある。
/// 紙とアプリで平均が食い違うと、どちらを信じればよいのか分からなくなるため。
struct ExportView: View {
    /// 経過画面から開いたときに、見ていたプランをそのまま選んでおくためのもの。
    var initialPlan: ObservationPlan?

    @Query(sort: \ObservationPlan.createdAt, order: .reverse) private var plans: [ObservationPlan]
    @Query(sort: \BowelMovement.date) private var movements: [BowelMovement]
    @Query(sort: \DailyRecord.date) private var dailyRecords: [DailyRecord]
    @Query private var targetRecords: [TargetRecord]

    @State private var selectedPlanID: PersistentIdentifier?
    @State private var period: ExportPeriod = .plan
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var files: ExportedFiles?
    @State private var failureMessage: String?

    private struct ExportedFiles {
        var pdf: URL
        var daily: URL
        var movements: URL
    }

    private static let previewScale: CGFloat = 280 / ReportLayout.pageSize.width

    var body: some View {
        Form {
            if plans.isEmpty {
                Section {
                    ContentUnavailableView(
                        "書き出せる記録がありません",
                        systemImage: "square.and.arrow.up",
                        description: Text("観察プランを作って記録すると、ここから書き出せます。")
                    )
                }
            } else {
                rangeSection
                outputSection
                previewSection
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("書き出し")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedPlanID == nil {
                selectedPlanID = (initialPlan ?? plans.first { $0.isActive } ?? plans.first)?.persistentModelID
            }
        }
        .task(id: fileKey) { await prepareFiles() }
    }

    // MARK: - 範囲

    @ViewBuilder
    private var rangeSection: some View {
        Section {
            if plans.count > 1 {
                Picker("プラン", selection: $selectedPlanID) {
                    ForEach(plans) { plan in
                        Text(plan.name).tag(Optional(plan.persistentModelID))
                    }
                }
            }

            Picker("期間", selection: $period) {
                ForEach(ExportPeriod.allCases) { period in
                    Text(period.label).tag(period)
                }
            }

            if period == .custom {
                DatePicker("開始", selection: $customStart, displayedComponents: .date)
                DatePicker("終了", selection: $customEnd, in: customStart..., displayedComponents: .date)
            }

            if let report {
                LabeledContent("書き出す範囲") {
                    Text("\(report.elapsedDays)日間（記録 \(report.recordedDays)日）")
                }
            }
        } header: {
            Text("範囲")
        } footer: {
            Text("フェーズ別の集計は、期間の一部だけを書き出した場合もフェーズ全体の記録から計算します。経過画面と同じ数値になるようにするためです。")
        }
    }

    // MARK: - 書き出し

    @ViewBuilder
    private var outputSection: some View {
        Section {
            if let report, !report.hasRecords {
                Label("この期間に記録がありません", systemImage: "tray")
                    .foregroundStyle(.secondary)
            } else if let failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if let files {
                shareRow(
                    files.pdf,
                    title: "PDF",
                    detail: "フェーズ別の集計・推移のグラフ・日別の記録・メモ",
                    systemImage: "doc.richtext"
                )
                shareRow(
                    files.daily,
                    title: "CSV（日別）",
                    detail: "1 日 1 行。表計算ソフトで開けます",
                    systemImage: "tablecells"
                )
                shareRow(
                    files.movements,
                    title: "CSV（排便の記録）",
                    detail: "1 件 1 行。時刻と 1 回ごとのメモも残ります",
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("準備しています…")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("書き出す")
        } footer: {
            Text("PDF は人に見せる用、CSV は控えや表計算ソフト用です。ファイルには記録した内容がそのまま入るので、共有先にはご注意ください。")
        }
    }

    private func shareRow(_ url: URL, title: String, detail: String, systemImage: String) -> some View {
        ShareLink(item: url) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }

    // MARK: - プレビュー

    @ViewBuilder
    private var previewSection: some View {
        if let report, report.hasRecords {
            let pages = ReportPagination.pages(for: report)
            Section {
                VStack(spacing: 8) {
                    ReportPageView(report: report, page: pages[0], pageNumber: 1, pageCount: pages.count)
                        .scaleEffect(Self.previewScale, anchor: .topLeading)
                        .frame(
                            width: ReportLayout.pageSize.width * Self.previewScale,
                            height: ReportLayout.pageSize.height * Self.previewScale
                        )
                        .overlay(Rectangle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .allowsHitTesting(false)
                        .accessibilityLabel("PDF の 1 ページ目のプレビュー")

                    Text("1ページ目 ・ 全\(pages.count)ページ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            } header: {
                Text("PDF のプレビュー")
            }
        }
    }

    // MARK: - 組み立て

    private var selectedPlan: ObservationPlan? {
        plans.first { $0.persistentModelID == selectedPlanID }
            ?? initialPlan
            ?? plans.first { $0.isActive }
            ?? plans.first
    }

    private var report: ObservationReport? {
        guard let plan = selectedPlan else { return nil }
        return ObservationReport.make(
            plan: plan,
            movements: movements,
            dailyRecords: dailyRecords,
            targetRecords: targetRecords,
            range: range(for: plan)
        )
    }

    private func range(for plan: ObservationPlan) -> ClosedRange<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let planRange = plan.observedRange() ?? today...today

        switch period {
        case .plan:
            return planRange
        case .recent30:
            return recent(days: 30, in: planRange, calendar: calendar)
        case .recent90:
            return recent(days: 90, in: planRange, calendar: calendar)
        case .custom:
            let start = calendar.startOfDay(for: min(customStart, customEnd))
            let end = calendar.startOfDay(for: max(customStart, customEnd))
            return start...end
        }
    }

    /// 直近 N 日。終わっているプランなら、その最終日から数える。
    /// 記録のありようがない未来ぶんを空欄で並べても仕方がないため。
    private func recent(days: Int, in planRange: ClosedRange<Date>, calendar: Calendar) -> ClosedRange<Date> {
        let end = planRange.upperBound
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return max(start, planRange.lowerBound)...end
    }

    /// 書き出し直しが要るかどうかの見分け。範囲か記録の件数が動いたら作り直す。
    private struct FileKey: Hashable {
        var planID: PersistentIdentifier?
        var start: Date?
        var end: Date?
        var movements: Int
        var dailyRecords: Int
        var targetRecords: Int
        /// 実施済みの件数も見る。実施した／しなかったの切り替えは行数を変えないので、
        /// 件数だけを見ていると集計が変わったのに書き出しが古いままになる。
        var completedTargetRecords: Int
    }

    private var fileKey: FileKey {
        let plan = selectedPlan
        let range = plan.map { self.range(for: $0) }
        return FileKey(
            planID: plan?.persistentModelID,
            start: range?.lowerBound,
            end: range?.upperBound,
            movements: movements.count,
            dailyRecords: dailyRecords.count,
            targetRecords: targetRecords.count,
            completedTargetRecords: targetRecords.count(where: \.isCompleted)
        )
    }

    private func prepareFiles() async {
        files = nil
        failureMessage = nil
        guard let report, report.hasRecords else { return }

        do {
            let directory = try ExportService.prepareDirectory()
            let stamp = report.generatedAt

            let pdf = directory.appending(
                path: ExportService.filename(planName: report.planName, suffix: "", extension: "pdf", date: stamp)
            )
            try ReportPDFRenderer.render(report, to: pdf)

            let daily = try ExportService.write(
                ExportService.dailyCSV(for: report),
                to: directory.appending(
                    path: ExportService.filename(planName: report.planName, suffix: "日別", extension: "csv", date: stamp)
                )
            )
            let movementFile = try ExportService.write(
                ExportService.movementCSV(for: report),
                to: directory.appending(
                    path: ExportService.filename(planName: report.planName, suffix: "排便", extension: "csv", date: stamp)
                )
            )

            files = ExportedFiles(pdf: pdf, daily: daily, movements: movementFile)
        } catch {
            failureMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview("記録あり") {
    NavigationStack { ExportView() }
        .modelContainer(SampleData.previewContainer)
}

#Preview("プランなし") {
    NavigationStack { ExportView() }
        .modelContainer(SampleData.emptyPreviewContainer)
}
#endif
