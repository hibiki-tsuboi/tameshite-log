import SwiftUI

/// ブリストル便形状スケール（1〜7）。
/// rawValue をそのまま平均計算に使えるよう、表示用の情報は計算プロパティに置く。
enum BristolScale: Int, CaseIterable, Codable, Identifiable, Sendable {
    case hardLumps = 1
    case hard = 2
    case slightlyHard = 3
    case normal = 4
    case slightlySoft = 5
    case mushy = 6
    case watery = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .hardLumps: "硬いコロコロ便"
        case .hard: "硬め"
        case .slightlyHard: "やや硬め"
        case .normal: "普通"
        case .slightlySoft: "やや柔らかい"
        case .mushy: "泥状"
        case .watery: "水様"
        }
    }

    var symbolName: String { "\(rawValue).circle.fill" }

    /// 硬い側から柔らかい側への並びを色でも示す。状態の良し悪しを表すものではない。
    var tint: Color {
        switch self {
        case .hardLumps, .hard: .brown
        case .slightlyHard, .normal, .slightlySoft: .green
        case .mushy, .watery: .orange
        }
    }
}

/// 腹痛・急な便意の強さ。集計できるよう 0〜3 で数値化する。
/// `none` は Optional の `.none` と紛らわしいため `absent` にしている。
enum SymptomLevel: Int, CaseIterable, Codable, Identifiable, Sendable {
    case absent = 0
    case mild = 1
    case moderate = 2
    case severe = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .absent: "なし"
        case .mild: "軽い"
        case .moderate: "中程度"
        case .severe: "強い"
        }
    }

    var tint: Color {
        switch self {
        case .absent: .secondary
        case .mild: .yellow
        case .moderate: .orange
        case .severe: .red
        }
    }
}

/// 全体的な体調・腹部の調子。数値が大きいほど「良い」と答えたことを表す。
enum ConditionLevel: Int, CaseIterable, Codable, Identifiable, Sendable {
    case poor = 0
    case fair = 1
    case good = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .good: "良い"
        case .fair: "普通"
        case .poor: "悪い"
        }
    }

    var symbolName: String {
        switch self {
        case .good: "face.smiling"
        case .fair: "face.dashed"
        case .poor: "cloud.rain"
        }
    }

    var tint: Color {
        switch self {
        case .good: .green
        case .fair: .secondary
        case .poor: .indigo
        }
    }
}
