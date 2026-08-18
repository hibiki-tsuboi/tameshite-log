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

            // このカードには保存ボタンがない。排便の記録だけがシートと「保存」で、
            // 同じ画面に 2 つの流儀が並ぶので、書かない側であることは書いておく。
            Text("体調とメモは入力するとすぐ保存されます。あとから何度でも書き直せます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } accessory: {
            // 保存された合図。いつ保存されるのかは、この時刻が動くことで伝わる。
            // 中身が空の行は片付けられる対象なので、保存済みとは名乗らせない。
            if let record, !record.isEmpty {
                Text("\(Formatting.timestamp(record.updatedAt, on: day)) に保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .task(id: record?.persistentModelID) {
            let stored = record?.note ?? ""
            if stored != note { note = stored }
        }
        .onChange(of: note) { _, newValue in
            guard newValue != record?.note else { return }
            let record = store.ensureDailyRecord(for: day)
            record.note = newValue
            // 体調の選択と揃えてここでも進める。進めないと、メモだけ書いた日の
            // 保存時刻が画面を離れるまで動かず、保存されていないように見える。
            record.updatedAt = .now
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
