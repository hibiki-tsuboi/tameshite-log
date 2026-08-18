import SwiftUI

/// フェーズの色。グラフの帯と一覧のバッジで同じ色を使い、
/// グラフを見たときにどの期間の話か目で追えるようにする。
enum PhasePalette {
    private static let accents: [Color] = [.teal, .indigo, .pink, .orange, .purple, .cyan]

    /// 並び順（プラン内のフェーズの位置）で色を決める。
    /// 「いつもの状態」は比較の基準なので、常に主張しないグレーにしておく。
    static func color(type: PhaseType, index: Int) -> Color {
        guard type != .baseline else { return .gray }
        return accents[index % accents.count]
    }
}
