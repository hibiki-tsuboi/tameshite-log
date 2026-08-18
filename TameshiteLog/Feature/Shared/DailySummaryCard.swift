import SwiftUI
import SwiftData

/// 1 日のまとめ。すべて任意入力なので、書かれるまで DailyRecord は作らない。
struct DailySummaryCard: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Query private var records: [DailyRecord]
    @State private var note: String = ""

    init(day: Date) {
        self.day = day
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _records = Query(filter: #Predicate<DailyRecord> { $0.date >= start && $0.date < end })
    }

    private var record: DailyRecord? { records.first }
    private var store: ObservationStore { ObservationStore(context: context) }

    var body: some View {
        SectionCard(title: "1日のまとめ", systemImage: "text.line.first.and.arrowtriangle.forward") {
            ConditionSelector(title: "全体的な体調", selection: condition(\.overallCondition))
            ConditionSelector(title: "腹部の調子", selection: condition(\.abdominalCondition))

            VStack(alignment: .leading, spacing: 8) {
                Text("メモ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("気づいたこと（任意）", text: $note, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
            }
        }
        .task(id: record?.persistentModelID) {
            let stored = record?.note ?? ""
            if stored != note { note = stored }
        }
        .onChange(of: note) { _, newValue in
            guard newValue != record?.note else { return }
            store.ensureDailyRecord(for: day).note = newValue
        }
        .onDisappear {
            // 入力途中で消すとカーソルが飛ぶので、掃除は画面を離れるときにまとめて行う。
            if let record { store.pruneIfEmpty(record) }
        }
    }

    private func condition(_ keyPath: ReferenceWritableKeyPath<DailyRecord, ConditionLevel?>) -> Binding<ConditionLevel?> {
        Binding(
            get: { record?[keyPath: keyPath] },
            set: { newValue in
                let record = store.ensureDailyRecord(for: day)
                record[keyPath: keyPath] = newValue
                record.updatedAt = .now
            }
        )
    }
}
