import SwiftUI
import SwiftData

/// 1 日分の排便記録の一覧。今日画面とカレンダーの日別画面で共有する。
struct MovementListCard: View {
    var title: String = "排便の記録"
    var movements: [BowelMovement]
    var onSelect: (BowelMovement) -> Void
    var onDelete: (BowelMovement) -> Void

    var body: some View {
        SectionCard(title: title, systemImage: "list.bullet") {
            if movements.isEmpty {
                Text("まだ記録がありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(movements.enumerated()), id: \.element.persistentModelID) { index, movement in
                        if index > 0 { Divider() }
                        Button {
                            onSelect(movement)
                        } label: {
                            MovementRow(movement: movement)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("編集", systemImage: "pencil") { onSelect(movement) }
                            Button("削除", systemImage: "trash", role: .destructive) { onDelete(movement) }
                        }
                        .accessibilityAction(named: "削除") { onDelete(movement) }
                    }
                }
            }
        }
    }
}

struct MovementRow: View {
    var movement: BowelMovement

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: movement.bristolScale.symbolName)
                .font(.title2)
                .foregroundStyle(movement.bristolScale.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(movement.bristolScale.label)
                        .font(.body)
                    Spacer(minLength: 8)
                    Text(Formatting.time(movement.recordedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                let details = symptomChips
                if !details.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(details, id: \.text) { chip in
                            Text(chip.text)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(chip.tint.opacity(0.15), in: .capsule)
                                .foregroundStyle(chip.tint)
                        }
                    }
                }

                if !movement.note.isEmpty {
                    Text(movement.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var symptomChips: [(text: String, tint: Color)] {
        var chips: [(String, Color)] = []
        if movement.abdominalPain != .absent {
            chips.append(("腹痛 \(movement.abdominalPain.label)", movement.abdominalPain.tint))
        }
        if movement.urgency != .absent {
            chips.append(("急な便意 \(movement.urgency.label)", movement.urgency.tint))
        }
        return chips
    }

    private var accessibilityDescription: String {
        var parts = [
            Formatting.time(movement.recordedAt),
            "ブリストル\(movement.bristolScale.rawValue) \(movement.bristolScale.label)",
        ]
        if movement.abdominalPain != .absent { parts.append("腹痛 \(movement.abdominalPain.label)") }
        if movement.urgency != .absent { parts.append("急な便意 \(movement.urgency.label)") }
        if !movement.note.isEmpty { parts.append(movement.note) }
        return parts.joined(separator: "、")
    }
}
