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

        #if DEBUG
        let usesScreenshotValues = movement == nil
            && ProcessInfo.processInfo.arguments.contains("-recordSample")
        #else
        let usesScreenshotValues = false
        #endif

        let calendar = Calendar.current
        let initialTime: Date
        if let movement {
            initialTime = movement.recordedAt
        } else if calendar.isDateInToday(day) {
            initialTime = .now
        } else {
            initialTime = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        }

        _bristolScale = State(initialValue: movement?.bristolScale ?? (usesScreenshotValues ? .slightlySoft : nil))
        _recordedAt = State(initialValue: initialTime)
        _abdominalPain = State(initialValue: movement?.abdominalPain ?? (usesScreenshotValues ? .mild : .absent))
        _urgency = State(initialValue: movement?.urgency ?? (usesScreenshotValues ? .moderate : .absent))
        _note = State(initialValue: movement?.note ?? "")
    }

    private var isEditing: Bool { movement != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ObservationHeroPanel(tint: bristolScale?.tint ?? .accentColor) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("便の状態")
                                .font(.headline)
                            BristolScaleRail(selection: $bristolScale)
                        }
                    }

                    SectionCard(title: "記録した時刻", systemImage: "clock") {
                        DatePicker("時刻", selection: $recordedAt, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SectionCard(title: "からだの反応", systemImage: "waveform.path.ecg") {
                        SymptomSelector(title: "腹痛", selection: $abdominalPain)
                        Divider()
                        SymptomSelector(title: "急な便意", selection: $urgency)
                    }

                    SectionCard(title: "メモ", systemImage: "text.alignleft") {
                        TextField("気づいたこと（任意）", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(12)
                            .background(ObservationTheme.raisedSurface, in: .rect(cornerRadius: 14))
                    }

                    if isEditing {
                        Button("この記録を削除", systemImage: "trash", role: .destructive) {
                            deleteMovement()
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color.red.opacity(0.09), in: .rect(cornerRadius: 16))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .readableWidth()
                .dismissesKeyboardOnBackgroundTap()
            }
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

/// 7 行のフォームではなく、硬い側から水様までを一続きの尺度として選ぶ。
private struct BristolScaleRail: View {
    @Binding var selection: BristolScale?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                ForEach(BristolScale.allCases) { scale in
                    let isSelected = selection == scale
                    Button {
                        withAnimation(.snappy) { selection = scale }
                    } label: {
                        Text("\(scale.rawValue)")
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            // 選んだ側の文字は白ではなく黒。`scale.tint` はシステム色で、
                            // 緑も橙もライト・ダークとも明るい側にあるため、白を乗せると
                            // 2.2:1 まで落ちる（17pt bold は大文字扱いなので基準は 3:1）。
                            // 塗りの色は硬い側から水様までの並びを示しているので変えず、
                            // 前景を反転させる。黒なら茶でも 6:1、緑と橙では 9:1 を超える。
                            //
                            // 選んでいない側も、同じ色の文字を薄い同色の上に置いていて
                            // 読みにくかった。数字は `.primary` にして、色は背景に残す。
                            .foregroundStyle(isSelected ? Color.black : Color.primary)
                            .background(
                                // 選んでいない側の色を 0.13 から上げる。数字を `.primary` に
                                // したぶん、硬い側から水様までの並びを示す色が薄い背景だけに
                                // 残る。0.13 のままだとライトで 7 つがほぼ同じ灰色に見えて、
                                // 並びが色でも分かるという `BristolScale.tint` の意図が消える。
                                isSelected ? scale.tint : scale.tint.opacity(0.26),
                                in: .circle
                            )
                            .overlay {
                                if isSelected {
                                    Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ブリストル\(scale.rawValue) \(scale.label)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }

            HStack {
                Text("硬い")
                Spacer()
                Text("水様")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 9) {
                Image(systemName: selection?.symbolName ?? "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(selection?.tint ?? Color.secondary)
                Text(selection?.label ?? "1〜7から選んでください")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(ObservationTheme.raisedSurface.opacity(0.82), in: .rect(cornerRadius: 14))

            Text("ブリストル便形状スケール（1: 硬い 〜 7: 水様）です。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
#Preview {
    BowelMovementEditor(day: .now)
        .modelContainer(SampleData.previewContainer)
}
#endif
