import SwiftUI
import SwiftData

/// 排便の記録シート。新規作成と編集を兼ねる。
///
/// 「開く → 便の状態を選ぶ → 保存」で終わるよう、最初の画面に選択肢が全部見えている状態にする。
/// 時刻は現在時刻が入っているので、そのままで構わない。
struct BowelMovementEditor: View {
    let day: Date
    var movement: BowelMovement?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var bristolScale: BristolScale?
    @State private var recordedAt: Date
    @State private var abdominalPain: SymptomLevel
    @State private var urgency: SymptomLevel
    @State private var note: String

    init(day: Date, movement: BowelMovement? = nil) {
        self.day = day
        self.movement = movement

        let calendar = Calendar.current
        let initialTime: Date
        if let movement {
            initialTime = movement.recordedAt
        } else if calendar.isDateInToday(day) {
            initialTime = .now
        } else {
            initialTime = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }

        _bristolScale = State(initialValue: movement?.bristolScale)
        _recordedAt = State(initialValue: initialTime)
        _abdominalPain = State(initialValue: movement?.abdominalPain ?? .absent)
        _urgency = State(initialValue: movement?.urgency ?? .absent)
        _note = State(initialValue: movement?.note ?? "")
    }

    private var isEditing: Bool { movement != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(BristolScale.allCases) { scale in
                        Button {
                            bristolScale = scale
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: scale.symbolName)
                                    .font(.title2)
                                    .foregroundStyle(scale.tint)
                                Text(scale.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if bristolScale == scale {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .accessibilityLabel("ブリストル\(scale.rawValue) \(scale.label)")
                        .accessibilityAddTraits(bristolScale == scale ? [.isSelected] : [])
                    }
                } header: {
                    Text("便の状態")
                } footer: {
                    Text("ブリストル便形状スケール（1: 硬い 〜 7: 水様）です。")
                }

                Section("時刻") {
                    DatePicker("記録した時刻", selection: $recordedAt, displayedComponents: .hourAndMinute)
                }

                Section("腹痛") {
                    SymptomSelector(title: "腹痛", selection: $abdominalPain)
                }

                Section("急な便意") {
                    SymptomSelector(title: "急な便意", selection: $urgency)
                }

                Section("メモ") {
                    TextField("任意", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if isEditing {
                    Section {
                        Button("この記録を削除", systemImage: "trash", role: .destructive) {
                            deleteMovement()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            // 既定はスクロールで即閉じる。指の動きに追従させて、他の画面と揃える。
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "記録を編集" : "排便を記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(bristolScale == nil)
                }
            }
        }
    }

    private func save() {
        guard let bristolScale else { return }
        let store = ObservationStore(context: context)

        if let movement {
            movement.updateRecordedAt(recordedAt)
            movement.bristolScale = bristolScale
            movement.abdominalPain = abdominalPain
            movement.urgency = urgency
            movement.note = note
        } else {
            store.addMovement(
                at: recordedAt,
                bristolScale: bristolScale,
                abdominalPain: abdominalPain,
                urgency: urgency,
                note: note
            )
        }
        dismiss()
    }

    private func deleteMovement() {
        guard let movement else { return }
        ObservationStore(context: context).delete(movement)
        dismiss()
    }
}

#if DEBUG
#Preview {
    BowelMovementEditor(day: .now)
        .modelContainer(SampleData.previewContainer)
}
#endif
