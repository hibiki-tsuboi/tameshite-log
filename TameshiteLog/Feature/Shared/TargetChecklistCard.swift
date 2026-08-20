import SwiftUI
import SwiftData

/// その日の観察対象と実施状況。薬なら服用の有無にあたる。
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

        /// 行の 2 行目。丸の形だけでは、まだ手をつけていない日なのか記録した結果なのかを
        /// 一目で読み取りにくい。ここまでは種類名（薬・サプリ…）を出していたが、
        /// 名前を見れば分かるものより、その日どうなっているかを置くほうが要る。
        /// 脚注のタップ順と同じ語を使って、次にどこへ切り替わるのかと対応させる。
        var caption: String {
            switch self {
            case .untracked: "未記録"
            case .completed: "実施した"
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
        let mark: Mark = record(for: target).map { $0.isCompleted ? .completed : .skipped } ?? .untracked

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
                    Text(mark.caption)
                        .font(.caption)
                        .foregroundStyle(mark.tint)
                }
                Spacer(minLength: 8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(target.name) を\(mark.accessibilityAction)")
        .accessibilityValue(mark.caption)
        .accessibilityAddTraits(mark == .completed ? [.isSelected] : [])
        .padding(.vertical, 8)
    }

    /// 「実施しなかった」が比較に使われることは、× の付いた行そのものが言う。
    /// まだ 1 つも付いていないあいだだけ、脚注でその比較があることを知らせる。
    ///
    /// 記録が日単位であることは常に書く。1 日に何回かあるものをどう付けるかは
    /// ○ か × かを選ぶ前の疑問で、行の見た目からは読み取れない。
    private var footerText: String {
        let cycle = "タップで「実施した」→「実施しなかった」→「未記録」と切り替わります。"
        let unit = "1 日に何回かあるものは、全部できた日を「実施した」にします。"
        guard !hasSkippedRow else { return cycle + unit }
        return cycle + unit + "実施した日と実施しなかった日は、経過画面で見くらべられます。"
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
