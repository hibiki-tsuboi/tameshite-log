import SwiftUI

/// 良い / 普通 / 悪い の 3 択。選択済みの項目をもう一度押すと未選択に戻せる。
/// 任意入力なので「取り消せること」を大事にしている。
struct ConditionSelector: View {
    var title: String
    @Binding var selection: ConditionLevel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(ConditionLevel.allCases.reversed()) { level in
                    let isSelected = selection == level
                    Button {
                        selection = isSelected ? nil : level
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: level.symbolName)
                                .font(.title3)
                            Text(level.label)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? level.tint.opacity(0.18) : Color(.tertiarySystemFill),
                            in: .rect(cornerRadius: 12)
                        )
                        .overlay {
                            // 選んだ合図を塗りの色だけに持たせない。「普通」は良し悪しを
                            // 表さない色なので塗りが未選択とほとんど同じ濃さになり、
                            // 押しても変わっていないように見える。枠線ならどの段階でも同じ強さで出る。
                            if isSelected {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(level.tint, lineWidth: 2)
                            }
                        }
                        .foregroundStyle(isSelected ? level.tint : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(level.label)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }
}

/// 腹痛・急な便意の 4 段階。入力を止めないよう横並びのセグメントにする。
struct SymptomSelector: View {
    var title: String
    @Binding var selection: SymptomLevel

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(SymptomLevel.allCases) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.segmented)
    }
}
