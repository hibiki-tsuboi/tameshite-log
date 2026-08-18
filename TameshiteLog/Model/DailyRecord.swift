import Foundation
import SwiftData

/// 1 日 1 件の「まとめ」。任意入力なので、書かれなければ作られない。
///
/// 排便記録とは独立させている。まとめを書かなくても排便だけ記録できるようにするため。
@Model
final class DailyRecord {
    #Unique<DailyRecord>([\.date])

    /// startOfDay へ丸めた日付。
    var date: Date = Date.distantPast
    var overallCondition: ConditionLevel?
    var abdominalCondition: ConditionLevel?
    var note: String = ""
    var updatedAt: Date = Date.distantPast

    init(
        date: Date,
        overallCondition: ConditionLevel? = nil,
        abdominalCondition: ConditionLevel? = nil,
        note: String = "",
        calendar: Calendar = .current
    ) {
        self.date = calendar.startOfDay(for: date)
        self.overallCondition = overallCondition
        self.abdominalCondition = abdominalCondition
        self.note = note
        self.updatedAt = .now
    }

    /// 何も書かれていないまとめは残さず消せるようにしておく。
    var isEmpty: Bool {
        overallCondition == nil
            && abdominalCondition == nil
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
