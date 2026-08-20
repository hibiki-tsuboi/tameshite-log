import Foundation
import SwiftData

/// 観察対象をその日に実施したかどうか。薬なら「飲んだ／飲んでいない」にあたる。
///
/// 1 日 1 対象につき 1 件で、実施した時刻は持たない。比較は日を「実施した日」と
/// 「実施しなかった日」に分けて平均を見くらべるだけなので、1 日のどこで実施したかは結果に効かない。
@Model
final class TargetRecord {
    /// startOfDay へ丸めた日付。
    var date: Date = Date.distantPast
    var target: ObservationTarget?
    var isCompleted: Bool = false

    init(
        date: Date,
        target: ObservationTarget?,
        isCompleted: Bool = false,
        calendar: Calendar = .current
    ) {
        self.date = calendar.startOfDay(for: date)
        self.target = target
        self.isCompleted = isCompleted
    }
}
