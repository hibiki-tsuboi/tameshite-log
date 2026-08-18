import SwiftUI
import SwiftData

/// その日の観察対象と実施状況。薬なら服用の有無と服用時刻にあたる。
struct TargetChecklistCard: View {
    var title: String = "観察対象"
    let day: Date
    let targets: [ObservationTarget]

    @Environment(\.modelContext) private var context
    @Query private var records: [TargetRecord]

    init(title: String = "観察対象", day: Date, targets: [ObservationTarget]) {
        self.title = title
        self.day = day
        self.targets = targets
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _records = Query(filter: #Predicate<TargetRecord> { $0.date >= start && $0.date < end })
    }

    private var store: ObservationStore { ObservationStore(context: context) }

    var body: some View {
        SectionCard(title: title, systemImage: "checkmark.circle") {
            if targets.isEmpty {
                Text("このフェーズに観察対象は登録されていません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(targets.enumerated()), id: \.element.persistentModelID) { index, target in
                        if index > 0 { Divider() }
                        row(for: target)
                    }
                }
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// その日の記録の状態。「実施しなかった」と「まだ書いていない」を分けて持つ。
    /// この 2 つを同じ見た目にすると、実施の有無で記録を見くらべられるのに気づけない。
    private enum Mark {
        case untracked
        case completed
        case skipped

        var symbolName: String {
            switch self {
            case .untracked: "circle"
            case .completed: "checkmark.circle.fill"
            case .skipped: "xmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .untracked: .secondary
            case .completed: .accentColor
            case .skipped: .orange
            }
        }

        var caption: String? {
            switch self {
            case .untracked: nil
            case .completed: nil
            // 「実施しなかった」とだけ書くと、これが比較の片側として数えられることが画面から読めない。
            // 押し間違いで × にした人がその場で気づけるよう、状態ではなく結果を書く。
            case .skipped: "実施しなかった日として比較に使います"
            }
        }

        /// 次にタップしたらどうなるかを読み上げる。
        var accessibilityAction: String {
            switch self {
            case .untracked: "実施した記録にする"
            case .completed: "実施しなかった記録にする"
            case .skipped: "未記録に戻す"
            }
        }
    }

    @ViewBuilder
    private func row(for target: ObservationTarget) -> some View {
        let record = self.record(for: target)
        let mark: Mark = record.map { $0.isCompleted ? .completed : .skipped } ?? .untracked
        let isCompleted = mark == .completed

        HStack(spacing: 12) {
            Button {
                store.toggleTarget(target, on: day)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: mark.symbolName)
                        .font(.title2)
                        .foregroundStyle(mark.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.name)
                            .foregroundStyle(.primary)
                        Text(mark.caption ?? target.type.label)
                            .font(.caption)
                            .foregroundStyle(mark.caption == nil ? Color.secondary : mark.tint)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(target.name) を\(mark.accessibilityAction)")
            .accessibilityValue(mark.caption ?? "")
            .accessibilityAddTraits(isCompleted ? [.isSelected] : [])

            if isCompleted, let record {
                // 実施時刻はあとから直せるようにしておく。飲んだ時間を思い出して記録する場面が多いため。
                DatePicker(
                    "実施時刻",
                    selection: Binding(
                        get: { record.completedAt ?? day },
                        set: { store.updateCompletionTime(record, to: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
        .padding(.vertical, 8)
    }

    /// 「実施しなかった」が比較に使われることは、× の付いた行そのものが言う。
    /// まだ 1 つも付いていないあいだだけ、脚注でその比較があることを知らせる。
    private var footerText: String {
        let cycle = "タップで「実施した」→「実施しなかった」→「未記録」と切り替わります。"
        guard !hasSkippedRow else { return cycle }
        return cycle + "実施した日と実施しなかった日は、経過画面で見くらべられます。"
    }

    private var hasSkippedRow: Bool {
        targets.contains { target in
            record(for: target).map { !$0.isCompleted } ?? false
        }
    }

    private func record(for target: ObservationTarget) -> TargetRecord? {
        let id = target.persistentModelID
        return records.first { $0.target?.persistentModelID == id }
    }
}
