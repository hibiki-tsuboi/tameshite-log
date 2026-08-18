import Foundation
import SwiftData

/// 観察の対象。薬に限定せず「変えてみたこと」全般を表す。
/// 薬専用にしないため、名前は Medication ではなく ObservationTarget にしている。
enum TargetType: String, CaseIterable, Codable, Identifiable, Sendable {
    case medication
    case supplement
    case food
    case exercise
    case lifestyle
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .medication: "薬"
        case .supplement: "サプリ"
        case .food: "食事"
        case .exercise: "運動"
        case .lifestyle: "生活習慣"
        case .other: "その他"
        }
    }

    var symbolName: String {
        switch self {
        case .medication: "pills.fill"
        case .supplement: "leaf.fill"
        case .food: "fork.knife"
        case .exercise: "figure.run"
        case .lifestyle: "bed.double.fill"
        case .other: "circle.dashed"
        }
    }
}

@Model
final class ObservationTarget {
    var name: String = ""
    var type: TargetType = TargetType.medication
    var note: String = ""
    var createdAt: Date = Date.distantPast

    /// 同じ対象を複数のフェーズで使い回せるよう多対多にしている。
    /// （例：「コレバイン」を単独フェーズと併用フェーズの両方で観察する）
    @Relationship(inverse: \ObservationPhase.targets)
    var phases: [ObservationPhase] = []

    @Relationship(deleteRule: .cascade, inverse: \TargetRecord.target)
    var records: [TargetRecord] = []

    init(name: String, type: TargetType = .medication, note: String = "", createdAt: Date = .now) {
        self.name = name
        self.type = type
        self.note = note
        self.createdAt = createdAt
    }
}
