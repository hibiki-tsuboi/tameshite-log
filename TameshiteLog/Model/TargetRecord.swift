import Foundation
import SwiftData

/// 観察対象をその日に実施したかどうか。薬なら「飲んだ／飲んでいない」にあたる。
@Model
final class TargetRecord {
    /// startOfDay へ丸めた日付。
    var date: Date = Date.distantPast
    var target: ObservationTarget?
    /// 実施した時刻。薬なら服用時刻。
    var completedAt: Date?
    var isCompleted: Bool = false

    init(
        date: Date,
        target: ObservationTarget?,
        completedAt: Date? = nil,
        isCompleted: Bool = false,
        calendar: Calendar = .current
    ) {
        self.date = calendar.startOfDay(for: date)
        self.target = target
        self.completedAt = completedAt
        self.isCompleted = isCompleted
    }

    func markCompleted(at time: Date = .now) {
        isCompleted = true
        completedAt = time
    }

    func markNotCompleted() {
        isCompleted = false
        completedAt = nil
    }
}
