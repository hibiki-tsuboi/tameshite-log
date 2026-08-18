import SwiftUI
import SwiftData

/// その日の観察対象と実施状況。薬なら服用の有無と服用時刻にあたる。
struct TargetChecklistCard: View {
    let day: Date
    let targets: [ObservationTarget]

    @Environment(\.modelContext) private var context
    @Query private var records: [TargetRecord]

    init(day: Date, targets: [ObservationTarget]) {
        self.day = day
        self.targets = targets
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _records = Query(filter: #Predicate<TargetRecord> { $0.date >= start && $0.date < end })
    }

    private var store: ObservationStore { ObservationStore(context: context) }

    var body: some View {
        SectionCard(title: "今日の観察対象", systemImage: "checkmark.circle") {
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
            }
        }
    }

    @ViewBuilder
    private func row(for target: ObservationTarget) -> some View {
        let record = self.record(for: target)
        let isCompleted = record?.isCompleted ?? false

        HStack(spacing: 12) {
            Button {
                store.toggleTarget(target, on: day)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isCompleted ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.name)
                            .foregroundStyle(.primary)
                        Text(target.type.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(target.name) を\(isCompleted ? "実施済みから未実施に戻す" : "実施済みにする")")
            .accessibilityAddTraits(isCompleted ? [.isSelected] : [])

            if isCompleted, let record {
                // 実施時刻はあとから直せるようにしておく。飲んだ時間を思い出して記録する場面が多いため。
                DatePicker(
                    "実施時刻",
                    selection: Binding(
                        get: { record.completedAt ?? day },
                        set: { record.completedAt = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }
        }
        .padding(.vertical, 8)
    }

    private func record(for target: ObservationTarget) -> TargetRecord? {
        let id = target.persistentModelID
        return records.first { $0.target?.persistentModelID == id }
    }
}
