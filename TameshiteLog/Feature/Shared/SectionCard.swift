import SwiftUI

/// 画面を構成する基本のカード。ヘルスケアやジャーナルに近い、余白のある見た目に揃える。
struct SectionCard<Content: View, Accessory: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text(title)
                    } icon: {
                        if let systemImage { Image(systemName: systemImage) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Spacer(minLength: 8)
                    accessory
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

extension SectionCard where Accessory == EmptyView {
    init(title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, systemImage: systemImage, content: content, accessory: { EmptyView() })
    }
}

extension View {
    /// 横に広い画面でカードが間延びしないよう、本文の幅を読みやすいところで止めて中央に置く。
    func readableWidth(_ maxWidth: CGFloat = 700) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

/// 数値ひとつを見せる小さなタイル。今日の集計とフェーズ集計で共有する。
struct StatTile: View {
    var title: String
    var value: String
    var caption: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// フェーズの種類を示す小さなラベル。
///
/// フェーズ名をそのまま種類名（「いつもの状態」など）にしている場合は、
/// 同じ言葉が二度並ぶだけなので何も描かない。
struct PhaseBadge: View {
    var type: PhaseType
    var color: Color
    var phaseName: String?

    var body: some View {
        if phaseName != type.label {
            Label(type.label, systemImage: type.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.15), in: .capsule)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            SectionCard(title: "今日の記録", systemImage: "list.bullet") {
                HStack {
                    StatTile(title: "排便回数", value: "3回")
                    StatTile(title: "平均ブリストル", value: "5.3")
                }
            }
            SectionCard(title: "フェーズ", systemImage: "flask") {
                PhaseBadge(type: .intervention, color: .teal)
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
