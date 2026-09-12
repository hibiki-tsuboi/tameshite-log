import SwiftUI
import SwiftData

/// 「記録する」だけではなく、期間を区切って見くらべるアプリだと伝えるための共通 UI。
/// 保存形式や集計には関わらず、画面の見え方だけをここに集める。
enum ObservationTheme {
    static let ink = Color(red: 0.04, green: 0.34, blue: 0.29)
    static let mint = Color(red: 0.42, green: 0.84, blue: 0.73)
    static let sand = Color(red: 0.96, green: 0.91, blue: 0.78)

    static var surface: Color { Color(.secondarySystemBackground) }
    static var raisedSurface: Color { Color(.tertiarySystemBackground) }
    static var hairline: Color { Color.primary.opacity(0.08) }
}

/// 主要画面の一番上に置く、通常の白いカードとは違う階層のパネル。
struct ObservationHeroPanel<Content: View>: View {
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    init(tint: Color = .accentColor, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background {
                LinearGradient(
                    colors: [tint.opacity(0.24), ObservationTheme.surface.opacity(0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(.rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.10), radius: 20, y: 10)
    }
}

/// プランの期間を横一列で見せる。このアプリ固有の「時間を区切る」考え方を全画面で共有する。
struct PhaseJourneyStrip: View {
    let plan: ObservationPlan
    var currentPhase: ObservationPhase?

    private var visiblePhases: [ObservationPhase] {
        Array(plan.orderedPhases.suffix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("観察の流れ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if plan.orderedPhases.count > visiblePhases.count {
                    Text("直近\(visiblePhases.count)期間")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(alignment: .top, spacing: 5) {
                ForEach(visiblePhases) { phase in
                    let isCurrent = phase.persistentModelID == currentPhase?.persistentModelID
                    let color = color(for: phase)

                    VStack(alignment: .leading, spacing: 7) {
                        Capsule()
                            .fill(color.opacity(isCurrent ? 1 : 0.34))
                            .frame(height: isCurrent ? 8 : 5)
                            .frame(maxHeight: 8, alignment: .bottom)

                        Text(phase.name)
                            .font(.caption.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? .primary : .secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)

                        if isCurrent {
                            Text("現在")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(color)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                }
            }
        }
    }

    private func color(for phase: ObservationPhase) -> Color {
        let index = plan.orderedPhases.firstIndex {
            $0.persistentModelID == phase.persistentModelID
        } ?? 0
        return PhasePalette.color(type: phase.type, index: index)
    }
}

/// 設定をタブから外し、主要画面共通の右上に置く。3 タブとも同じ角に出すので、
/// 「設定はどこ」の答えがタブによって変わらない。
///
/// 記号は歯車。ellipsis は iOS では「この画面のその他の操作」を指すので、画面と
/// 関係のない全体設定の入口には使わない。比較と履歴では、その画面のアクション
/// （書き出す・今月）の隣に並ぶため、同じ意味に読まれると実際に紛らわしかった。
private struct MainSettingsAccessModifier: ViewModifier {
    #if DEBUG
    @State private var isShowingSettings = ProcessInfo.processInfo.arguments.contains("-showSettings")
    #else
    @State private var isShowingSettings = false
    #endif

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("設定", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityHint("観察プランやアプリの設定を開きます")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
                    .presentationDragIndicator(.visible)
            }
    }
}

extension View {
    func mainSettingsAccess() -> some View {
        modifier(MainSettingsAccessModifier())
    }
}

struct ObservationPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(ObservationTheme.ink.opacity(configuration.isPressed ? 0.78 : 1), in: .capsule)
            .shadow(color: ObservationTheme.ink.opacity(configuration.isPressed ? 0.08 : 0.22), radius: 14, y: 7)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
